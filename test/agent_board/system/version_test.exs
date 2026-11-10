defmodule AgentBoard.System.VersionTest do
  @moduledoc "Served, available and the state between them."
  use ExUnit.Case, async: false

  alias AgentBoard.System.Version

  test "served is cached and non-empty" do
    first = Version.served()
    assert is_binary(first)
    assert Version.served() == first
  end

  test "status carries the served sha and a state" do
    status = Version.status()
    assert is_binary(status.served)
    assert is_boolean(status.dirty)
    assert is_list(status.commits)
    assert status.state in [:up_to_date, :behind, :restart, :ahead, :unknown]
  end

  test "the checkout can be current while this VM still serves an older sha" do
    assert Version.state("abc1234", "abc1234", 0) == :up_to_date
    assert Version.state("abc1234", "def5678", 0) == :restart
    assert Version.state("abc1234", "def5678", 2) == :behind
    assert Version.state("abc1234", "def5678", nil) == :unknown
  end

  describe "refresh_shared/1" do
    setup do
      :persistent_term.erase(:agent_board_fetched_at)
      on_exit(fn -> :persistent_term.erase(:agent_board_fetched_at) end)
    end

    test "open tabs share one fetch" do
      test = self()

      fetch = fn ->
        send(test, :fetched)
        {:ok, "abc"}
      end

      assert {:ok, "abc"} = Version.refresh_shared(fetch)
      assert_received :fetched

      :persistent_term.put(:agent_board_available, "abc")
      assert {:ok, "abc"} = Version.refresh_shared(fetch)
      refute_received :fetched
    end

    test "a failed fetch is tried again by the next tab" do
      test = self()

      failing = fn ->
        send(test, :fetched)
        {:error, :no_network}
      end

      assert {:error, :no_network} = Version.refresh_shared(failing)
      assert {:error, :no_network} = Version.refresh_shared(failing)
      assert_received :fetched
      assert_received :fetched
    end

    test "a tab that arrives during a fetch does not start another" do
      test = self()

      running =
        Task.async(fn ->
          Version.refresh_shared(fn ->
            send(test, {:fetching, self()})

            receive do
              :finish -> {:ok, "abc"}
            end
          end)
        end)

      assert_receive {:fetching, fetcher}
      :persistent_term.put(:agent_board_available, "known")

      assert {:ok, "known"} = Version.refresh_shared(fn -> flunk("a second fetch") end)

      send(fetcher, :finish)
      assert {:ok, "abc"} = Task.await(running)
    end
  end

  test "without a fetch, available is nil and the state is unknown" do
    :persistent_term.erase(:agent_board_available)
    assert Version.available() == nil
    assert Version.status().state == :unknown
  end
end
