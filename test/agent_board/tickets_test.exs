defmodule AgentBoard.TicketsTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Tickets

  describe "by_number/1" do
    defp ticket(id, numbers, updated, ended \\ nil),
      do: %{"id" => id, "numbers" => numbers, "updated_at" => updated, "ended_at" => ended}

    test "an open ticket speaks for its issue, else the most recently updated" do
      old = ticket("old", [7, 8], ~U[2026-11-09 10:00:00Z], ~U[2026-11-09 10:00:00Z])
      newer = ticket("newer", [8], ~U[2026-11-09 12:00:00Z], ~U[2026-11-09 12:00:00Z])
      open = ticket("open", [7], ~U[2026-11-08 10:00:00Z])

      for tickets <- [[old, newer, open], [open, newer, old]] do
        assert Tickets.by_number(tickets) == %{7 => open, 8 => newer}
      end
    end
  end

  describe "stages/2" do
    @started ~U[2026-11-10 12:00:00Z]
    @ticket %{"started_at" => @started, "own_threads" => []}

    defp worktree(at),
      do: %{step: %{kind: :edit, code: "lib/a.ex", note: nil}, last_activity_at: at}

    test "no ticket has no stages" do
      assert Tickets.stages(nil, nil) == []
    end

    test "is analysis until the worktree changes after the start" do
      analysis = [{:analysis, "now"}, {:code, "todo"}, {{:pull_request, nil}, "todo"}]

      assert Tickets.stages(@ticket, nil) == analysis
      assert Tickets.stages(@ticket, %{step: nil, last_activity_at: nil}) == analysis
      # the base commit is older than the assignment
      assert Tickets.stages(@ticket, worktree(~U[2026-11-10 11:00:00Z])) == analysis
      assert Tickets.stages(Map.delete(@ticket, "started_at"), worktree(@started)) == analysis
    end

    test "is code once the agent changed the worktree" do
      assert Tickets.stages(@ticket, worktree(~U[2026-11-10 12:04:00Z])) ==
               [{:analysis, "done"}, {:code, "now"}, {{:pull_request, nil}, "todo"}]
    end

    test "a second attempt keeps the code of the first" do
      first = ~U[2026-11-10 10:00:00Z]

      ticket =
        Map.put(@ticket, "assignments", [%{"started_at" => first}, %{"started_at" => @started}])

      assert [{:analysis, "done"}, {:code, "now"} | _] =
               Tickets.stages(ticket, worktree(~U[2026-11-10 11:00:00Z]))
    end

    test "is the pull request once the ticket opened one, whatever the worktree says" do
      ticket = %{@ticket | "own_threads" => [41, 40]}

      assert Tickets.stages(ticket, nil) ==
               [{:analysis, "done"}, {:code, "done"}, {{:pull_request, 41}, "now"}]
    end
  end
end
