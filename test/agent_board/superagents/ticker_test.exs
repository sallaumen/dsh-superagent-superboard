defmodule AgentBoard.Superagents.TickerTest do
  @moduledoc "The ticker never runs two reconciles at once: each acts on the list it read."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Superagents}
  alias AgentBoard.Superagents.{Superagent, Ticker}

  defmodule BlockingManager do
    @moduledoc "A manager whose stop waits until the test releases it."
    @behaviour AgentBoard.Superagents.Manager

    @impl true
    def status(_superagent), do: {:ok, %{state: "ready", detail: nil}}

    @impl true
    def stop(_superagent) do
      send(:ticker_test, {:stopping, self()})

      receive do
        :release -> :ok
      end
    end

    @impl true
    def start(_superagent), do: :ok
    @impl true
    def pause(_superagent, _paused), do: :ok
    @impl true
    def scale(_superagent, _workers), do: :ok
    @impl true
    def access(_superagent), do: {:ok, %{allowed: []}}
    @impl true
    def allow(_superagent, _login), do: :ok
    @impl true
    def disallow(_superagent, _login), do: :ok
    @impl true
    def requeue(_superagent, _issue), do: {:ok, false}
    @impl true
    def github_source(_agent), do: {:error, :unreachable}
    @impl true
    def identity(_superagent), do: {:error, :unreachable}
    @impl true
    def prompts(_superagent), do: {:error, :unreachable}
    @impl true
    def save_prompts(_superagent, _config, _revision), do: {:error, :unreachable}
  end

  setup do
    previous = Application.get_env(:agent_board, :superagent_manager)
    Application.put_env(:agent_board, :superagent_manager, BlockingManager)
    Process.register(self(), :ticker_test)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :superagent_manager, previous),
        else: Application.delete_env(:agent_board, :superagent_manager)
    end)

    {:ok, repo} = Board.add_repository("fixture", "superagent")

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-fixture",
        port: 3194,
        state_dir: "/tmp/fixture-superagent-ticker"
      })

    {:ok, superagent} = Superagents.set_desired(superagent, "stopped")
    %{superagent: superagent}
  end

  test "a tick while a reconcile is still stopping an agent starts no second one", %{
    superagent: superagent
  } do
    ticker = start_supervised!({Ticker, name: __MODULE__.Ticker, interval: :manual})

    send(ticker, :tick)
    assert_receive {:stopping, stopping}, 2_000

    send(ticker, :tick)
    refute_receive {:stopping, _}, 300

    # The owner presses Start while the stop is still in flight.
    {:ok, _} = Superagents.set_desired(Repo.get!(Superagent, superagent.id), "running")

    ref = Process.monitor(stopping)
    send(stopping, :release)
    assert_receive {:DOWN, ^ref, :process, _, _}, 2_000

    assert Repo.get!(Superagent, superagent.id).desired_state == "running"
  end
end
