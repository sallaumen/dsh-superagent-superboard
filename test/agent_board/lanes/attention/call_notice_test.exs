defmodule AgentBoard.Lanes.Attention.CallNoticeTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.Repository
  alias AgentBoard.Lanes.Attention.CallNotice

  @context %{
    now: ~U[2026-11-16 12:00:00Z],
    tz_offset: 180,
    repository: %Repository{name: "board"}
  }
  @task %{id: 71, number: 12, held: true, released_at: ~U[2026-11-16 11:50:00Z]}

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "a failed call says the board tried; retry requests confirmation for the right task" do
    assert {why, [%{label: "Call again", release: phrase}, %{label: "View details", task_id: 71}]} =
             CallNotice.content(:failed, @task, @context)

    assert why ==
             "**The call to the agent did not complete.** The board tried today at 08:50 and does not try again on its own."

    assert phrase ==
             "Call the agent on #12 in board? It starts now, even if a dependency is still open."
  end

  test "an unanswered call describes the posted mention and lack of a ticket" do
    task = %{@task | held: false}
    {why, _actions} = CallNotice.content(:unanswered, task, @context)

    assert why ==
             "**Called 10 min ago and the agent did not start.** The board posted the mention today at 08:50 and no agent ticket names this issue."
  end

  test "the queued lane shows only the two classified problems with their original attention ages" do
    base = Map.put(@task, :title, "Queued work")
    no_ticket = %{base | held: false, id: 72, number: 13}
    has_ticket = %{no_ticket | id: 73, number: 14}
    in_flight = %{base | id: 74, number: 15, released_at: DateTime.add(@context.now, -15)}
    board = %{queued: [has_ticket, in_flight, no_ticket, base]}

    cards =
      AgentBoard.Lanes.needs(@context.repository, board,
        now: @context.now,
        tz_offset: 180,
        stall_after: 120,
        tickets_by_number: %{14 => %{}}
      )

    assert [
             %{id: 71, kind: :unanswered, age_seconds: 600},
             %{id: 72, kind: :unanswered, age_seconds: 480}
           ] = cards

    assert hd(cards).why =~ "did not complete"
    assert List.last(cards).why =~ "no agent ticket"
  end
end
