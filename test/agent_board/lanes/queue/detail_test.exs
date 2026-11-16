defmodule AgentBoard.Lanes.Queue.DetailTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Queue.Detail

  @now ~U[2026-11-09 12:00:00Z]
  @calls %{now: @now, tickets: %{}, stall_after: 900}

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "a held row shows open dependencies instead of its relationship until a call fails" do
    row = %{number: 21, held: true, released_at: nil}

    assert Detail.describe(row, {:unblocks, 9}, [2, 7], @calls) == %{
             sub: "waiting for #2, #7",
             stuck: nil
           }

    assert Detail.describe(row, nil, [], @calls).sub == "waiting for its dependencies"
    failed = %{row | released_at: DateTime.add(@now, -60)}

    assert Detail.describe(failed, {:unblocks, 9}, [2], @calls) == %{
             sub: "unblocks #9",
             stuck: "the call to the agent did not complete"
           }
  end

  test "a runner assignment follows the relationship; an unanswered call gets a separate warning" do
    row = %{number: 21, held: false, released_at: DateTime.add(@now, -900)}

    calls = %{
      @calls
      | tickets: %{21 => %{"assignments" => [%{"created_at" => DateTime.add(@now, -120)}]}}
    }

    assert Detail.describe(row, {:split_from, 7}, [], calls) == %{
             sub: "split from #7 · entered the agent's queue 2 min ago",
             stuck: nil
           }

    assert Detail.describe(row, nil, [], @calls) == %{
             sub: nil,
             stuck: "called 15 min ago, the agent did not start"
           }
  end
end
