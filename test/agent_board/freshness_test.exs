defmodule AgentBoard.FreshnessTest do
  @moduledoc "The board's one truth: live only when every source answered within its cadence."
  use ExUnit.Case, async: true

  alias AgentBoard.Board.Event
  alias AgentBoard.Freshness

  @now ~U[2026-11-06 12:00:00Z]

  defp event(kind, seconds_ago, errors \\ 0) do
    %Event{
      kind: kind,
      inserted_at: DateTime.add(@now, -seconds_ago, :second),
      payload: %{"errors" => errors}
    }
  end

  defp agent(ok \\ true, tickets \\ []) do
    %{ok: ok, at: DateTime.add(@now, -20, :second), tickets: tickets, error: nil}
  end

  defp snapshot(opts) do
    Freshness.snapshot(
      Keyword.merge(
        [
          now: @now,
          connected: true,
          last_attempt: event("sync", 30),
          last_success: event("sync", 30),
          agent: agent()
        ],
        opts
      )
    )
  end

  test "a fresh sync and an answering runner are live" do
    result = snapshot([])

    assert result.state == :live
    assert result.live?
    refute result.frozen?
    assert result.age_sec == 30

    assert [%{code: :github_current}, %{code: :agent_current}, %{code: :queue_current}] =
             result.sources

    assert Enum.all?(result.sources, &(&1.kind == :run))
  end

  test "a sync older than the cadence is delayed but not frozen" do
    old = event("sync", 7 * 60)
    result = snapshot(last_attempt: old, last_success: old)

    assert result.state == :delayed
    refute result.frozen?
    assert result.age_sec == 420
  end

  test "a failed attempt freezes the board even near a good sync" do
    result = snapshot(last_attempt: event("sync_error", 10), last_success: event("sync", 60))

    assert result.state == :offline
    assert result.frozen?

    assert [%{code: :github_failed, kind: :blocked, attempted_at: %DateTime{}} | _] =
             result.sources
  end

  test "a disconnected socket is reconnecting, not live" do
    result = snapshot(connected: false)

    assert result.state == :reconnecting
    refute result.live?
  end

  test "no sync at all is unknown, never zero" do
    result = snapshot(last_attempt: nil, last_success: nil)

    assert result.state == :unknown
    assert result.age_sec == nil
    assert result.at == nil
  end

  test "a sync with item errors is not live" do
    result = snapshot(last_attempt: event("sync", 20, 2), last_success: event("sync", 20, 2))

    assert result.state == :delayed
    assert [%{code: :github_errors, kind: :stale, error_count: 2} | _] = result.sources
  end

  test "an unavailable runner downgrades a fresh GitHub sync" do
    result = snapshot(agent: agent(false))

    assert result.state == :delayed
    assert [_github, %{code: :agent_unavailable, kind: :blocked}, _queue] = result.sources
  end

  test "a running ticket without a recent heartbeat is called out" do
    stale_agent = %{
      ok: true,
      at: DateTime.add(@now, -5 * 60, :second),
      tickets: [%{"assignment" => "running", "idle_at" => nil}],
      error: nil
    }

    result = snapshot(agent: stale_agent)

    assert result.state == :delayed
    assert [_github, %{code: :agent_stale, kind: :stale}, _queue] = result.sources
  end

  test "a rate limit is a delay that lifts by itself, not a lost connection" do
    limited = %Event{
      kind: "sync_error",
      inserted_at: DateTime.add(@now, -60, :second),
      payload: %{"reason" => "GitHub rate limited", "rate_limited" => true, "retry_after" => 300}
    }

    snap = snapshot(last_attempt: limited, last_success: event("sync", 300))

    assert snap.state == :delayed
    refute snap.frozen?
    assert [%{code: :github_rate_limited, retry_after: 300} | _] = snap.sources
  end
end
