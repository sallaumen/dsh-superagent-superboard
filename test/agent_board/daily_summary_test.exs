defmodule AgentBoard.DailySummaryTest do
  @moduledoc """
  The summary of the day on a wall clock: once per local day after the
  configured hour, across a sleeping Mac, repeated ticks and restarts.
  """
  use AgentBoard.DataCase, async: false

  alias AgentBoard.AutoRetry.Attempt
  alias AgentBoard.{Board, DailySummary, Repo, Settings}
  alias AgentBoard.Board.{Event, PullRequest, Task}
  alias AgentBoard.DailySummary.Entry
  alias Ecto.Adapters.SQL.Sandbox

  # The owner's clock (São Paulo, UTC-3), passed as an offset so the test
  # does not depend on the machine's zone: 11:00Z is 08:00 local.
  @offset -180

  defp utc(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    at
  end

  defp spend(_since, _until), do: %{status: :none, reason: nil}
  defp usage(_since, _until), do: %{}

  defp tick(iso, opts \\ []),
    do:
      DailySummary.tick(
        Keyword.merge(
          [now: utc(iso), utc_offset: @offset, spend: &spend/2, usage: &usage/2],
          opts
        )
      )

  defp entries, do: Repo.all(from e in Entry, order_by: e.local_date)

  describe "the wall clock" do
    test "with the Mac asleep at 8h, the summary goes out once on waking" do
      assert tick("2026-11-07T10:59:00Z") == :not_due
      assert entries() == []

      # Asleep from 07:59 to 10:17: no tick ran at 08:00.
      assert {:generated, entry} = tick("2026-11-07T13:17:00Z")
      assert entry.local_date == ~D[2026-11-07]
      assert entry.generated_at == utc("2026-11-07T13:17:00Z")

      assert tick("2026-11-07T13:18:00Z") == :exists
      assert length(entries()) == 1
    end

    test "two ticks in a row and a restart of the ticker generate nothing more" do
      opts = [now: utc("2026-11-07T11:05:00Z"), utc_offset: @offset, spend: &spend/2]

      start = fn ->
        pid =
          start_supervised!(
            {DailySummary, name: :daily_summary_test, interval: :manual, tick_opts: opts},
            id: :daily_summary_test
          )

        Sandbox.allow(Repo, self(), pid)
        pid
      end

      pid = start.()
      send(pid, :tick)
      send(pid, :tick)
      :sys.get_state(pid)
      assert length(entries()) == 1

      :ok = stop_supervised(:daily_summary_test)
      pid = start.()
      send(pid, :tick)
      :sys.get_state(pid)

      assert length(entries()) == 1
    end

    test "concurrent ticks claim one row" do
      results =
        1..4
        |> Enum.map(fn _ -> Elixir.Task.async(fn -> tick("2026-11-07T12:00:00Z") end) end)
        |> Enum.map(&Elixir.Task.await/1)

      assert Enum.count(results, &match?({:generated, _}, &1)) == 1
      assert Enum.count(results, &(&1 == :exists)) == 3
      assert length(entries()) == 1
    end

    test "the next day waits for the hour and covers everything since the last summary" do
      {:generated, first} = tick("2026-11-07T11:02:00Z")

      assert tick("2026-11-08T10:30:00Z") == :not_due
      assert {:generated, second} = tick("2026-11-08T11:01:00Z")

      assert second.local_date == ~D[2026-11-08]
      assert second.window_start == first.window_end
      assert second.window_end == utc("2026-11-08T11:01:00Z")
    end

    test "the first summary covers the last 24 hours" do
      {:generated, entry} = tick("2026-11-07T11:00:00Z")

      assert entry.window_start == utc("2026-11-06T11:00:00Z")
    end

    test "a long sleep covers at most seven days" do
      {:generated, _first} = tick("2026-11-01T11:00:00Z")
      {:generated, entry} = tick("2026-11-20T11:00:00Z")

      assert entry.window_start == utc("2026-11-13T11:00:00Z")
    end

    test "the local date comes from the owner's clock, not from UTC" do
      # 01:30Z on the 8th is 22:30 on the 7th in São Paulo.
      assert {:generated, entry} = tick("2026-11-08T01:30:00Z")
      assert entry.local_date == ~D[2026-11-07]
    end

    test "a configured hour waits for it" do
      :ok = DailySummary.put_settings(%{"at" => "09:30"})

      assert tick("2026-11-07T12:29:00Z") == :not_due
      assert {:generated, _entry} = tick("2026-11-07T12:30:00Z")
    end

    test "switched off, nothing is generated" do
      :ok = DailySummary.put_settings(%{"enabled" => "false"})

      assert tick("2026-11-07T15:00:00Z") == :disabled
      assert entries() == []
    end

    test "a generated summary is broadcast" do
      DailySummary.subscribe()
      {:generated, entry} = tick("2026-11-07T11:00:00Z")

      assert_receive {:daily_summary, :generated, id}
      assert id == entry.id
    end
  end

  describe "settings" do
    test "default to on at 08:00" do
      assert DailySummary.settings() == %{enabled: true, at: ~T[08:00:00]}
    end

    test "store the switch and the hour" do
      :ok = DailySummary.put_settings(%{"enabled" => "false", "at" => "07:15"})

      assert DailySummary.settings() == %{enabled: false, at: ~T[07:15:00]}
      assert Settings.get("daily_summary_at") == "07:15"
    end

    test "refuse an hour that is not HH:MM and keep the saved one" do
      :ok = DailySummary.put_settings(%{"at" => "06:45"})

      assert DailySummary.put_settings(%{"at" => "25:99"}) == {:error, :invalid_time}
      assert DailySummary.put_settings(%{"at" => "oito"}) == {:error, :invalid_time}
      assert DailySummary.settings().at == ~T[06:45:00]
    end
  end

  describe "the content" do
    setup do
      {:ok, repo} = Board.add_repository("sallaumen", "agent-board")
      %{repo: repo}
    end

    test "counts the merges of the window only", %{repo: repo} do
      pull(repo, 10, "Fora da janela", "2026-11-06T10:00:00Z", [4])
      pull(repo, 11, "Mesclado ontem à noite", "2026-11-07T01:00:00Z", [5, 6])
      pull(repo, 12, "Mesclado de manhã", "2026-11-07T10:30:00Z", [6])

      {:generated, entry} = tick("2026-11-07T11:00:00Z")
      merged = entry.content["merged"]

      assert merged["count"] == 2
      # #4 was outside the window; #6 was closed twice and counts once.
      assert merged["issues"] == 2
      assert Enum.map(merged["items"], & &1["number"]) == [12, 11]
      assert hd(merged["items"])["repo"] == "sallaumen/agent-board"
    end

    test "says what still needs the owner, blocked first", %{repo: repo} do
      task(repo, 1, "Quebrou o build", "blocked")
      task(repo, 2, "Qual cor?", "question")
      task(repo, 3, "Pronto para revisão", "ready")
      task(repo, 4, "Rodando", "running")
      task(repo, 5, "Parada de propósito", "blocked", stopped: true)

      {:generated, entry} = tick("2026-11-07T11:00:00Z")
      needs = entry.content["needs"]

      assert needs["blocked"] == 1
      assert needs["waiting"] == 2
      assert [%{"number" => 1, "state" => "blocked"} | _] = needs["items"]
      refute Enum.any?(needs["items"], &(&1["number"] in [4, 5]))
    end

    test "counts the automatic retries the board made in the window" do
      retry("t-1", "a-1", "retried", "2026-11-07T02:00:00Z")
      retry("t-1", "a-2", "retried", "2026-11-07T03:00:00Z")
      retry("t-2", "a-3", "unreachable", "2026-11-07T04:00:00Z")
      retry("t-3", "a-4", "retried", "2026-11-05T04:00:00Z")

      {:generated, entry} = tick("2026-11-07T11:00:00Z")

      assert entry.content["retries"] == %{"sent" => 3, "tasks" => 2, "not_accepted" => 1}
    end

    test "counts the sync failures of the window", %{repo: repo} do
      event(repo, "sync_error", "2026-11-07T03:00:00Z")
      event(repo, "sync_error", "2026-11-05T03:00:00Z")
      event(repo, "sync", "2026-11-07T04:00:00Z")

      {:generated, entry} = tick("2026-11-07T11:00:00Z")

      assert entry.content["sync_errors"] == 1
    end

    test "names each executor's spending in its own currency, unknown without a source" do
      measured = fn _since, _until ->
        %{
          status: :measured,
          reason: nil,
          requests: 40,
          models: ["deepseek-flash"],
          cost: %{micros: 1_234_567, complete?: false}
        }
      end

      {:generated, entry} = tick("2026-11-07T11:00:00Z", spend: measured)

      assert [deepseek, claude, codex] = entry.content["spend"]

      assert deepseek == %{
               "executor" => "deepseek",
               "status" => "measured",
               "currency" => "USD",
               "micros" => 1_234_567,
               "complete" => false,
               "requests" => 40,
               "models" => ["deepseek-flash"]
             }

      assert claude == %{"executor" => "claude", "status" => "unknown", "reason" => "no_source"}
      assert codex == %{"executor" => "codex", "status" => "unknown", "reason" => "no_source"}
    end

    test "the ledger gives Claude its list price and Codex its weekly quota" do
      usage = fn _since, _until ->
        %{
          "claude_code" => %{
            source: "claude_code",
            status: :measured,
            requests: 30,
            models: ["claude-opus-5-5"],
            cost: %{micros: 2_000_000, complete?: true, currency: :usd}
          },
          "codex" => %{
            source: "codex",
            status: :none,
            requests: 0,
            quota: %{
              used_percent: 90.0,
              window_minutes: 10_080,
              resets_at: utc("2026-11-11T13:46:01Z"),
              observed_at: utc("2026-11-06T13:59:58Z")
            }
          }
        }
      end

      {:generated, entry} = tick("2026-11-07T11:00:00Z", usage: usage)

      assert [deepseek, claude, codex] = entry.content["spend"]
      assert deepseek["executor"] == "deepseek"

      assert claude == %{
               "executor" => "claude",
               "status" => "measured",
               "currency" => "USD",
               "reference" => "list",
               "quota" => "unknown",
               "micros" => 2_000_000,
               "complete" => true,
               "requests" => 30,
               "models" => ["claude-opus-5-5"]
             }

      assert codex == %{
               "executor" => "codex",
               "status" => "measured",
               "currency" => "quota",
               "percent" => 90.0,
               "window_minutes" => 10_080,
               "resets_at" => "2026-11-11T13:46:01Z",
               "requests" => 0
             }
    end

    test "a Codex ledger without a weekly quota is unknown, never zero" do
      usage = fn _since, _until ->
        %{"codex" => %{source: "codex", status: :none, requests: 0, quota: nil}}
      end

      {:generated, entry} = tick("2026-11-07T11:00:00Z", usage: usage)
      assert Enum.at(entry.content["spend"], 2)["status"] == "unknown"
      assert Enum.at(entry.content["spend"], 2)["reason"] == "no_quota"
    end

    test "an unreadable transcript is unknown, not a day without work" do
      unreadable = fn _since, _until ->
        %{status: :measured, requests: 0, unreadable: 1, cost: nil, models: []}
      end

      {:generated, entry} = tick("2026-11-07T11:00:00Z", spend: unreadable)

      assert hd(entry.content["spend"]) == %{
               "executor" => "deepseek",
               "status" => "unknown",
               "reason" => "unreadable"
             }
    end

    test "the spending reader gets the window" do
      test_pid = self()

      reader = fn since, until ->
        send(test_pid, {:window, since, until})
        %{status: :unavailable, reason: :zstd_missing}
      end

      {:generated, entry} = tick("2026-11-07T11:00:00Z", spend: reader)

      assert_received {:window, since, until}
      assert since == utc("2026-11-06T11:00:00Z")
      assert until == utc("2026-11-07T11:00:00Z")

      assert hd(entry.content["spend"]) == %{
               "executor" => "deepseek",
               "status" => "unknown",
               "reason" => "zstd_missing"
             }
    end
  end

  describe "on the board" do
    test "today's summary is visible until it is dismissed" do
      {:generated, entry} = tick("2026-11-07T11:00:00Z")
      now = utc("2026-11-07T15:00:00Z")

      assert DailySummary.visible(now: now, utc_offset: @offset).id == entry.id
      assert DailySummary.visible(now: utc("2026-11-08T11:00:00Z"), utc_offset: @offset) == nil

      DailySummary.subscribe()
      :ok = DailySummary.dismiss(entry.id)

      assert_receive {:daily_summary, :dismissed, _id}
      assert DailySummary.visible(now: now, utc_offset: @offset) == nil
    end
  end

  defp pull(repo, number, title, merged_at, closes) do
    Repo.insert!(%PullRequest{
      repository_id: repo.id,
      number: number,
      title: title,
      closes_issues: closes,
      state: "merged",
      url: "https://github.com/sallaumen/agent-board/pull/#{number}",
      merged_at: utc(merged_at)
    })
  end

  defp task(repo, number, title, state, attrs \\ []) do
    Repo.insert!(
      struct(
        %Task{
          repository_id: repo.id,
          number: number,
          title: title,
          state: state,
          url: "https://github.com/sallaumen/agent-board/issues/#{number}"
        },
        attrs
      )
    )
  end

  defp event(repo, kind, at) do
    Repo.insert!(%Event{repository_id: repo.id, kind: kind, subject: kind, inserted_at: utc(at)})
  end

  defp retry(ticket, assignment, outcome, at) do
    at = utc(at)

    Repo.insert!(%Attempt{
      ticket_id: ticket,
      assignment_id: assignment,
      attempt: 1,
      outcome: outcome,
      inserted_at: at,
      updated_at: at
    })
  end
end
