defmodule AgentBoard.Usage.ReportTest do
  @moduledoc "The usage ledger as numbers: per execution, per day, and in each executor's own currency."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.Board.{PullRequest, Task}
  alias AgentBoard.Usage.{Costs, Report}

  defp ledger(source, execution, day, attrs \\ %{}) do
    at = DateTime.new!(day, ~T[12:00:00], "Etc/UTC")

    Map.merge(
      %{
        source: source,
        execution_id: execution,
        day: day,
        cwd: "/tmp/arena-rogue",
        git_branch: "feat/x",
        model: "deepseek-flash",
        requests: 1,
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        cache_read_tokens: 0,
        cache_write_tokens: 0,
        first_at: at,
        last_at: at,
        inserted_at: at,
        updated_at: at
      },
      attrs
    )
    |> then(&Repo.insert_all("usage_ledger", [&1]))
  end

  test "each source keeps its own price and is never added to another" do
    day = ~D[2026-11-07]
    ledger("dsh", "ticket-1", day)
    ledger("claude_code", "session-1", day, %{model: "claude-opus-5-5"})

    assert [dsh, claude] = Report.daily(day)

    assert dsh.source == "dsh"
    assert dsh.cost.micros == 700_000
    assert dsh.cost.complete?

    assert claude.source == "claude_code"
    assert claude.cost.micros > 0
    assert claude.cost.complete?
    refute claude.cost.micros == dsh.cost.micros
  end

  test "an unpriced model makes the total a minimum, never zero" do
    day = ~D[2026-11-07]

    ledger("dsh", "ticket-1", day, %{model: "unknown-model"})

    assert [row] = Report.daily(day)
    assert row.cost == nil
  end

  test "the expected cost is the median execution cost of that executor" do
    day = Date.utc_today()

    # 1M input + 1M output = US$ 0.70; two more at US$ 1.40 and US$ 2.10.
    ledger("dsh", "ticket-1", day)
    ledger("dsh", "ticket-2", day, %{input_tokens: 2_000_000, output_tokens: 2_000_000})
    ledger("dsh", "ticket-3", day, %{input_tokens: 3_000_000, output_tokens: 3_000_000})

    costs = Report.expected_costs()
    assert %{micros: 1_400_000, complete?: true} = costs["dsh"]
    assert costs["codex"] == :unknown
  end

  test "a window reads Claude and DeepSeek from messages and Codex from the weekly quota" do
    since = DateTime.new!(~D[2026-11-06], ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(~D[2026-11-08], ~T[00:00:00], "Etc/UTC")
    at = DateTime.new!(~D[2026-11-07], ~T[10:00:00], "Etc/UTC")

    old = DateTime.new!(~D[2026-11-01], ~T[10:00:00], "Etc/UTC")

    Repo.insert_all("usage_messages", [
      %{
        source: "dsh",
        message_id: "old-dsh",
        execution_id: "ticket-old",
        at: old,
        day: ~D[2026-11-01],
        cwd: nil,
        git_branch: nil,
        model: "deepseek-flash",
        input_tokens: 1,
        output_tokens: 1,
        cache_read_tokens: 0,
        cache_write_tokens: 0
      },
      %{
        source: "claude_code",
        message_id: "m1",
        execution_id: "s1",
        at: at,
        day: ~D[2026-11-07],
        cwd: "/tmp/arena-rogue",
        git_branch: "feat/x",
        model: "claude-opus-5-5",
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        cache_read_tokens: 0,
        cache_write_tokens: 0
      }
    ])

    ledger("codex", "thread-1", ~D[2026-11-07], %{
      model: "gpt-6-sol",
      first_at: at,
      last_at: at
    })

    Repo.insert_all("usage_limits", [
      %{
        source: "codex",
        limit_id: "codex",
        plan_type: "chatgpt",
        primary_used_percent: 90.0,
        primary_window_minutes: 10_080,
        primary_resets_at: DateTime.new!(~D[2026-11-11], ~T[13:46:01], "Etc/UTC"),
        observed_at: at,
        inserted_at: at,
        updated_at: at
      }
    ])

    spend = Report.spend_window(since, until)

    assert %{status: :measured, cost: %{micros: micros}} = spend["claude_code"]
    assert micros > 0

    assert %{status: :measured, quota: %{used_percent: 90.0, window_minutes: 10_080}} =
             spend["codex"]

    assert %{status: :none} = spend["dsh"]
  end

  test "an executor summary counts tasks, direct sessions and the merge" do
    day = Date.utc_today()
    {:ok, repo} = AgentBoard.Board.add_repository("fixture", "panel")

    task =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, kind: "issue", number: 12, title: "Mapa"})
      |> Repo.insert!()

    Repo.update_all(
      from(t in Task, where: t.id == ^task.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -10 * 3600, :second)]
    )

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 3,
      title: "Mapa",
      state: "merged",
      merged_at: DateTime.utc_now() |> DateTime.truncate(:second),
      closes_issues: [12],
      head_ref: "feat/x"
    })
    |> Repo.insert!()

    ledger("claude_code", "session-1", day, %{
      model: "claude-opus-5-5",
      cwd: "/tmp/panel",
      git_branch: "feat/x"
    })

    ledger("claude_code", "session-2", day, %{
      model: "claude-opus-5-5",
      cwd: "/tmp/panel",
      git_branch: "HEAD"
    })

    ledger("claude_code", "session-3", day, %{
      model: "claude-opus-5-5",
      cwd: "/tmp/forrozin-page",
      git_branch: "main"
    })

    claude = Enum.find(Report.executors(day), &(&1.source == "claude_code"))

    assert claude.tasks_count == 1
    assert [%{number: 12}] = claude.tasks
    assert claude.merged.merged == 1
    assert claude.merged.rate == 1.0
    assert_in_delta claude.merged.median_hours, 10.0, 0.1
    assert claude.direct == [{"fixture/panel", 1}]
    assert claude.outside == [{"forrozin-page", 1}]
    assert claude.executions == 3
  end

  test "a source that never wrote a row is unknown, not zero" do
    since = DateTime.new!(~D[2026-11-06], ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(~D[2026-11-08], ~T[00:00:00], "Etc/UTC")

    assert %{status: :unknown, reason: :no_source} =
             Report.spend_window(since, until)["claude_code"]
  end

  test "the cost module never invents a price" do
    assert %{micros: 700_000, complete?: true} =
             Costs.cost("dsh", [
               %{model: "deepseek-flash", input_tokens: 1_000_000, output_tokens: 1_000_000}
             ])

    assert %{complete?: false} =
             Costs.cost("dsh", [
               %{
                 model: "deepseek-flash",
                 input_tokens: 1_000_000,
                 output_tokens: 1_000_000,
                 cache_read_tokens: 1_000_000
               }
             ])

    assert Costs.cost("dsh", [%{model: "not-in-the-table"}]) == nil
    assert Costs.cost("codex", [%{model: "gpt-6-sol"}]) == nil
  end
end
