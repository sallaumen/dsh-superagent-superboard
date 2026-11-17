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

  test "visible questions share one repository-scoped read and use only the newest agent comment" do
    {:ok, repo} = Board.add_repository("fixture", "visible-questions")
    {:ok, other} = Board.add_repository("fixture", "other-questions")
    one = task(repo, 71, "question")
    two = task(repo, 72, "question")
    elsewhere = task(other, 71, "question")
    comment(one, "agent", "Old question?")
    comment(one, "agent", "## Relatório do agente\n### Pergunta\nChoose a release")
    comment(one, "user", "User question?")
    comment(two, "agent", "Previously asked?")
    comment(two, "agent", "All settled.")
    comment(elsewhere, "agent", "Other repository?")
    comment(task(repo, 73, "question"), "agent", "Not requested?")
    # The higher comment id breaks an exact timestamp tie.
    Repo.update_all(from(c in Comment, where: c.task_id in ^[one.id, two.id]),
      set: [inserted_at: @now]
    )

    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    {cards, queries} = reads(fn -> Lanes.needs(repo, %{question: [one, two]}, now: @now) end)

    assert [
             %{number: 71, why: "**The agent asked:** Choose a release"},
             %{number: 72, why: neutral}
           ] = cards

    assert neutral =~ "waiting for your answer"
    assert length(queries) == 1
    assert Board.agent_questions(repo.id, [71, 72]) == %{71 => "Choose a release"}
    assert {%{}, []} = reads(fn -> Board.agent_questions(repo.id, []) end)
  end

  test "batched blockages read only current agent evidence for the requested repository and issues" do
    {:ok, repo} = Board.add_repository("fixture", "batched-blockages")
    {:ok, other} = Board.add_repository("fixture", "foreign-blockages")
    one = task(repo, 10, "blocked")
    two = task(repo, 20, "blocked")
    report = "## Relatório do agente\n### Bloqueio\n"

    comment(one, "agent", report <> "Old reason")
    comment(one, "agent", report <> "Missing key")
    comment(one, "user", report <> "User note")
    comment(two, "agent", report <> "Old reason")
    comment(two, "agent", "Now investigating")
    comment(task(other, 10, "blocked"), "agent", report <> "Foreign reason")
    comment(task(repo, 30, "blocked"), "agent", report <> "Not requested")

    Repo.update_all(from(c in Comment, where: c.task_id in ^[one.id, two.id]),
      set: [inserted_at: @now]
    )

    {sections, queries} = reads(fn -> Board.agent_blockages(repo.id, [10, 20, 10, 99]) end)
    assert sections == %{10 => "Missing key"}
    assert length(queries) == 1
    assert Board.agent_blockage(repo.id, 10) == "Missing key"
    assert {%{}, []} = reads(fn -> Board.agent_blockages(repo.id, []) end)
    assert {nil, []} = reads(fn -> Board.agent_blockage(repo.id, nil) end)
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
