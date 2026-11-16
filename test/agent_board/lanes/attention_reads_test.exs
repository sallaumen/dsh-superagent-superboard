defmodule AgentBoard.Lanes.AttentionReadsTest do
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Lanes}
  alias AgentBoard.Board.{Comment, Task}

  @now ~U[2026-11-16 15:00:00Z]

  test "an outage counts hidden work without reading its reports and keeps review and question cards" do
    {:ok, repo} = Board.add_repository("fixture", "outage-reads")
    review = task(repo, 10, "ready")
    question = task(repo, 11, "question")
    comment(question, "agent", "Which release?")
    visible = %{ready: [review], question: [question]}

    blocked = for n <- [91, 92], do: task(repo, n, "blocked")
    for t <- blocked, do: comment(t, "agent", "## Relatório do agente\n### Bloqueio\nMissing key")
    running = task(repo, 93, "running")
    failed = %{task(repo, 94, "queued") | held: true, released_at: DateTime.add(@now, -120)}

    board =
      Map.merge(visible, %{
        blocked: blocked,
        running: [running],
        queued: [failed],
        retrying: [task(repo, 95, "retrying")]
      })

    opts = [
      agent: :down,
      now: @now,
      stall_after: 60,
      silences: %{93 => %{seconds: 60, at: DateTime.add(@now, -60), source: :start}}
    ]

    {[%{waiting: 0}, review_card, question_card], baseline} =
      reads(fn -> Lanes.needs(repo, visible, opts) end)

    assert %{kind: :review, number: 10} = review_card
    assert %{kind: :question, number: 11, why: why} = question_card
    assert why =~ "Which release?"
    assert baseline != []
    {cards, observed} = reads(fn -> Lanes.needs(repo, board, opts) end)
    assert [%{kind: :agent_down, waiting: 5}, ^review_card, ^question_card] = cards
    assert observed == baseline
  end

  defp task(repo, number, state) do
    Repo.insert!(%Task{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: "Task #{number}",
      state: state,
      state_changed_at: @now
    })
  end

  defp comment(task, kind, body),
    do: Repo.insert!(%Comment{task_id: task.id, kind: kind, body: body})

  # Only record comment reads issued by the calling test process.
  def record(_event, _measurements, %{source: "comments", query: sql, params: params}, {pid, ref})
      when pid == self(),
      do: send(pid, {ref, sql, params})

  def record(_event, _measurements, _meta, _config), do: :ok

  defp reads(fun) do
    ref = make_ref()

    :ok =
      :telemetry.attach(ref, [:agent_board, :repo, :query], &__MODULE__.record/4, {self(), ref})

    try do
      {fun.(), collect(ref)}
    after
      :telemetry.detach(ref)
    end
  end

  defp collect(ref) do
    receive do
      {^ref, sql, params} -> [{sql, params} | collect(ref)]
    after
      0 -> []
    end
  end
end
