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

    # a row with no messages cannot say its hours: off-peak, and a minimum
    assert dsh.source == "dsh"
    assert dsh.cost.micros == 750_000
    refute dsh.cost.complete?

    assert claude.source == "claude_code"
    assert claude.cost.micros > 0
    assert claude.cost.complete?
    refute claude.cost.micros == dsh.cost.micros
  end

  test "a day-long ledger row pays each token at the rate of its message's hour" do
    day = ~D[2026-11-10]

    ledger("dsh", "ticket-1", day, %{
      input_tokens: 2_000_000,
      output_tokens: 1_000_000,
      cache_read_tokens: 2_000_000
    })

    message = fn id, at, output ->
      %{
        source: "dsh",
        message_id: id,
        execution_id: "ticket-1",
        at: at,
        day: day,
        cwd: "/tmp/arena-rogue",
        git_branch: "feat/x",
        model: "deepseek-flash",
        input_tokens: 1_000_000,
        output_tokens: output,
        cache_read_tokens: 1_000_000,
        cache_write_tokens: 0
      }
    end

    Repo.insert_all("usage_messages", [
      message.("peak", ~U[2026-11-10 07:30:00.000000Z], 0),
      message.("off-peak", ~U[2026-11-10 12:30:00.000000Z], 1_000_000)
    ])

    assert [row] = Report.rows(day, day)
    assert row.peak == %{input: 1_000_000, output: 0, cache_read: 1_000_000}

    # peak 0.30 + cache 0.006; off-peak 0.15 + 0.60 + cache 0.003
    assert [%{cost: %{micros: 1_059_000, complete?: true}}] = Report.daily(day)
  end

  test "an unpriced model makes the total a minimum, never zero" do
    day = ~D[2026-11-07]

    ledger("dsh", "ticket-1", day, %{model: "unknown-model"})

    assert [row] = Report.daily(day)
    assert row.cost == nil
  end

  test "the expected cost is the median execution cost of that executor" do
    day = Date.utc_today()

    # 1M input + 1M output off-peak = US$ 0.75; two more at US$ 1.50 and US$ 2.25.
    ledger("dsh", "ticket-1", day)
    ledger("dsh", "ticket-2", day, %{input_tokens: 2_000_000, output_tokens: 2_000_000})
    ledger("dsh", "ticket-3", day, %{input_tokens: 3_000_000, output_tokens: 3_000_000})

    costs = Report.expected_costs()
    assert %{micros: 1_500_000, complete?: false} = costs["dsh"]
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

  test "today is the owner's local day, not the UTC midnight" do
    at = fn iso -> DateTime.from_iso8601(iso) |> elem(1) end

    for {id, time} <- [
          {"m1", "2026-11-07T23:00:00Z"},
          {"m2", "2026-11-08T02:00:00Z"},
          {"m3", "2026-11-07T02:00:00Z"}
        ] do
      moment = at.(time)

      Repo.insert_all("usage_messages", [
        %{
          source: "claude_code",
          message_id: id,
          execution_id: "s-#{id}",
          at: moment,
          day: DateTime.to_date(moment),
          cwd: "/tmp/arena",
          git_branch: nil,
          model: "claude-opus-5-5",
          input_tokens: 1_000_000,
          output_tokens: 1_000_000,
          cache_read_tokens: 0,
          cache_write_tokens: 0
        }
      ])
    end

    today = Report.today(180, now: at.("2026-11-08T00:30:00Z"))

    assert today.day == ~D[2026-11-07]
    assert %{cost: %{micros: micros}} = today.by_source["claude_code"]
    assert micros == 2 * 32_300_000
  end

  test "a source that never wrote a row is unknown, not zero" do
    since = DateTime.new!(~D[2026-11-06], ~T[00:00:00], "Etc/UTC")
    until = DateTime.new!(~D[2026-11-08], ~T[00:00:00], "Etc/UTC")

    assert %{status: :unknown, reason: :no_source} =
             Report.spend_window(since, until)["claude_code"]
  end

  test "the weekly Codex quota is the newest wide window, not the first" do
    old = %{
      source: "codex",
      primary_used_percent: 0.0,
      primary_window_minutes: 10_080,
      observed_at: DateTime.new!(~D[2026-09-10], ~T[05:58:10], "Etc/UTC")
    }

    new = %{
      source: "codex",
      primary_used_percent: 90.0,
      primary_window_minutes: 10_080,
      observed_at: DateTime.new!(~D[2026-11-06], ~T[13:59:58], "Etc/UTC")
    }

    assert %{used_percent: 90.0} = Costs.codex_weekly([old, new])
    assert %{used_percent: 90.0} = Costs.codex_weekly([new, old])
  end

  # A reading taken before the window reset says nothing about this week: the
  # board's own Codex runs are refused by it, so nothing would read it again.
  test "a weekly window that already reset is not the current quota" do
    now = DateTime.utc_now()

    expired = %{
      source: "codex",
      primary_used_percent: 60.0,
      primary_window_minutes: 10_080,
      primary_resets_at: DateTime.add(now, -2, :day),
      observed_at: DateTime.add(now, -3, :day)
    }

    assert Costs.codex_weekly([expired]) == nil

    current = %{expired | primary_resets_at: DateTime.add(now, 2, :day)}
    assert %{used_percent: 60.0} = Costs.codex_weekly([current])
  end

  test "the cost module never invents a price" do
    message = %{
      model: "deepseek-flash",
      input_tokens: 1_000_000,
      output_tokens: 1_000_000,
      cache_read_tokens: 1_000_000
    }

    # a message pays the rate of its hour, cache reads included
    assert %{micros: 1_506_000, complete?: true} =
             Costs.cost("dsh", [Map.put(message, :at, ~U[2026-11-10 07:00:00Z])])

    assert %{micros: 753_000, complete?: true} =
             Costs.cost("dsh", [Map.put(message, :at, ~U[2026-11-10 12:00:00Z])])

    # no time to price it by: the off-peak rate, said to be a minimum
    assert %{micros: 753_000, complete?: false} = Costs.cost("dsh", [message])

    # a model with one rate needs no hour, and a message with no model has no price
    assert %{complete?: true} =
             Costs.cost("claude_code", [%{model: "claude-opus-5-5", input_tokens: 1}])

    assert Costs.cost("dsh", [%{model: "not-in-the-table"}]) == nil
    assert Costs.cost("codex", [%{model: "gpt-6-sol"}]) == nil
  end

  # Read from Claude Code's own `cost-state` lines on 2026-11-10, on the lines
  # that split 5-minute and 1-hour cache writes: fable-5-2 matches on 3 of 3
  # and haiku-5-5 on 7 of 8, to five decimals.
  test "fable-5-2 and haiku-5-5 have the list price Claude Code itself uses" do
    assert %{input: 5.0, output: 25.0, cache_read: 0.5, cache_write: 6.25} =
             Costs.prices("claude_code", "claude-fable-5-2")

    # A real haiku line: 1,009,421 in, 106,421 out, 13 web searches, US$ 0.28415.
    # The ledger does not count searches (US$ 0.01 each), so the tokens alone
    # are 0.28415 - 0.13.
    assert %{micros: 154_153, complete?: true} =
             Costs.cost("claude_code", [
               %{model: "claude-haiku-5-5", input_tokens: 1_009_421, output_tokens: 106_421}
             ])
  end

  # A real cost-state line of opus-4-8 (read on 2026-11-10): Claude Code's own
  # cost for these counts is US$ 8.02491. All ten lines on this machine match
  # 5.00 in / 25.00 out; the family's main model rate gave about half.
  test "opus-4-8 is priced at its own rate, not its family's" do
    assert %{micros: 8_024_914, complete?: true} =
             Costs.cost("claude_code", [
               %{
                 model: "claude-opus-4-8",
                 input_tokens: 136,
                 output_tokens: 45_953,
                 cache_read_tokens: 11_357_968,
                 cache_write_tokens: 191_428
               }
             ])
  end

  # A real opus-4-8 line whose cache writes were all 1-hour ones: Claude Code's
  # own cost is US$ 4.98922. At the 5-minute rate the same row gave 3.27.
  test "1-hour cache writes are priced at twice the input, as Claude Code does" do
    day = ~D[2026-11-07]

    ledger("claude_code", "session-1h", day, %{
      model: "claude-opus-4-8",
      input_tokens: 8,
      output_tokens: 4_130,
      cache_read_tokens: 607_287,
      cache_write_tokens: 458_229,
      cache_write_1h_tokens: 458_229
    })

    assert [%{cost: %{micros: 4_989_224, complete?: true}}] = Report.daily(day)
  end
end
