defmodule AgentBoard.Superagents.LeftoversTest do
  @moduledoc "Ended tickets' folders: measured, kept for a number of days, removed by the registry only."
  use AgentBoard.DataCase, async: false

  import Ecto.Query

  alias AgentBoard.{Actions, Board, LeftoversFixture, Repo, Superagents}
  alias AgentBoard.Actions.Decision
  alias AgentBoard.Superagents.{FakeManager, Leftovers, Ticker}

  setup do
    root = Path.join(System.tmp_dir!(), "leftovers-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = LeftoversFixture.build!(root)

    {:ok, repo} = Board.add_repository("fixture", "leftovers")

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-leftovers",
        port: 3197,
        state_dir: fixture.state
      })

    %{superagent: Superagents.get(superagent.id), dirs: fixture.dirs}
  end

  defp present(dirs), do: for({name, dir} <- dirs, File.dir?(dir), do: name) |> Enum.sort()

  defp decisions(action),
    do: Repo.all(from d in Decision, where: d.action == ^action, order_by: d.id)

  test "the survey says what could go and what stays, and removes nothing",
       %{superagent: sa, dirs: dirs} do
    assert {:ok, survey} = Leftovers.survey(sa)

    assert ["old", "recent"] = survey.folders |> Enum.map(& &1.name) |> Enum.sort()
    assert %{prs: 0, kept: 1, stray: 1, problem: nil} = survey
    assert survey.kb > 0

    today = Date.utc_today()
    assert [%{name: "old", outcome: "merged"}] = Leftovers.past(survey.folders, 30, today)
    assert Leftovers.past(survey.folders, :never, today) == []
    assert present(dirs) == ~w(dirty old open recent stray)
  end

  test "a project keeps its folders for 30 days until the owner says otherwise", %{superagent: sa} do
    assert Leftovers.days(sa) == 30

    assert {:ok, _text} =
             Actions.run(:set_agent_folder_days, %{superagent: sa, days: 7}, Actions.owner(:ui))

    assert Leftovers.days(sa) == 7

    assert {:ok, _text} =
             Actions.run(
               :set_agent_folder_days,
               %{superagent: sa, days: :never},
               Actions.owner(:ui)
             )

    assert Leftovers.days(sa) == :never
    assert Leftovers.put_days(sa, 3) == {:error, :invalid}
  end

  test "the daily retention removes only what is older than the project's days",
       %{superagent: sa, dirs: dirs} do
    assert Leftovers.sweep() == :ok

    # The uncommitted folder is as old, and stays; so does everything recent.
    assert present(dirs) == ~w(dirty open recent stray)

    assert [%{by: "folder_retention", via: "system", outcome: "ok", decision: "automatic"}] =
             decisions("sweep_agent_folders")

    # Nothing old is left: a second pass records nothing.
    assert Leftovers.sweep() == :ok
    assert length(decisions("sweep_agent_folders")) == 1

    assert {:ok, %{folders: [%{name: "recent"}]}} = Leftovers.survey(sa)
  end

  test "a project that keeps its folders is never swept", %{superagent: sa, dirs: dirs} do
    :ok = Leftovers.put_days(sa, :never)

    assert Leftovers.sweep() == :ok
    assert present(dirs) == ~w(dirty old open recent stray)
    assert decisions("sweep_agent_folders") == []
  end

  test "the red button needs its sentence, then removes every ended folder that is clean",
       %{superagent: sa, dirs: dirs} do
    params = %{superagent: sa}

    assert {:error, {:unconfirmed, _phrase}} =
             Actions.run(:clean_agent_leftovers, params, Actions.owner(:ui))

    assert present(dirs) == ~w(dirty old open recent stray)

    phrase = Actions.phrase(:clean_agent_leftovers, params, "pt-BR")

    assert {:ok, text} =
             Actions.run(:clean_agent_leftovers, params, Actions.owner(:ui), confirm: phrase)

    assert text =~ "2 pastas removidas"
    assert text =~ "1 mantida"
    assert present(dirs) == ~w(dirty open stray)
  end

  test "an agent with no database is an error to read, and the sweep goes on",
       %{superagent: sa} do
    File.rm!(Path.join(sa.state_dir, "orchestrator.sqlite"))

    assert {:error, reason} = Leftovers.survey(sa)
    assert reason =~ "no database"
    assert Leftovers.sweep() == :ok
  end

  describe "the ticker" do
    setup do
      {:ok, _pid} = FakeManager.start()
      previous = Application.get_env(:agent_board, :superagent_manager)
      Application.put_env(:agent_board, :superagent_manager, FakeManager)
      Application.put_env(:agent_board, :agent_folder_sweep, true)

      on_exit(fn ->
        Application.put_env(:agent_board, :agent_folder_sweep, false)

        if previous,
          do: Application.put_env(:agent_board, :superagent_manager, previous),
          else: Application.delete_env(:agent_board, :superagent_manager)
      end)
    end

    test "starts the retention on the first tick of a day and not again", %{dirs: dirs} do
      ticker = start_supervised!({Ticker, name: __MODULE__.Ticker, interval: :manual})

      send(ticker, :tick)
      assert %{swept_on: today, sweep: sweep} = :sys.get_state(ticker)
      assert today == Date.utc_today()

      ref = Process.monitor(sweep)
      assert_receive {:DOWN, ^ref, :process, ^sweep, _reason}, 10_000
      assert present(dirs) == ~w(dirty open recent stray)

      send(ticker, :tick)
      assert %{sweep: ^sweep} = :sys.get_state(ticker)
      assert length(decisions("sweep_agent_folders")) == 1
    end
  end
end
