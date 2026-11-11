defmodule AgentBoard.Freshness do
  @moduledoc """
  How fresh the board is, from the sources that actually answered.

  The board never says "live" from the socket alone. GitHub answers through the
  last sync, the runner answers through its ticket database, and the local
  queue answers through the read that rendered this page. A failed GitHub
  attempt freezes the board even when the last good sync is recent: the data
  is saved, but it is no longer being confirmed.
  """

  @github_ttl 6 * 60
  @stale_ttl 15 * 60
  @agent_running_ttl 2 * 60

  @type state :: :live | :delayed | :reconnecting | :offline | :unknown

  @doc "The expected GitHub cadence, with one minute of grace over the 5-minute cron."
  def github_ttl, do: @github_ttl

  @doc "After this age a successful sync is no longer trusted as current."
  def stale_ttl, do: @stale_ttl

  @doc """
  Whether the repository's stored counts can no longer be shown as current:
  no attempt yet, a failed attempt, or a success older than `stale_ttl/0`.
  A rate limit is a delay that lifts by itself, so it keeps the data trusted,
  exactly as `snapshot/1` does for the header.
  """
  @spec untrusted?(map() | nil, DateTime.t()) :: boolean()
  def untrusted?(nil, _now), do: true

  def untrusted?(last_attempt, now) do
    not rate_limited?(last_attempt) and
      (last_attempt.kind == "sync_error" or age_sec(now, last_attempt.inserted_at) > @stale_ttl)
  end

  @doc """
  The board's freshness snapshot.

  `last_attempt` is the newest sync event (success or error), `last_success`
  the newest successful one, and `agent` the result of `AgentBoard.AgentState.snapshot/0`.
  """
  @spec snapshot(keyword() | map()) :: map()
  def snapshot(opts) do
    opts = Map.new(opts)
    now = Map.get(opts, :now, DateTime.utc_now())
    connected = Map.get(opts, :connected, true)
    last_attempt = Map.get(opts, :last_attempt)
    last_success = Map.get(opts, :last_success)
    agent = Map.get(opts, :agent, %{ok: false, at: nil, tickets: [], error: :unknown})

    age = age_sec(now, last_success && last_success.inserted_at)
    state = state(connected, last_attempt, last_success, age, agent, now)
    at = last_success && last_success.inserted_at

    %{
      state: state,
      age_sec: age,
      at: at,
      frozen?: state == :offline,
      live?: state == :live,
      sources: sources(now, state, last_attempt, last_success, age, agent)
    }
  end

  defp state(connected, last_attempt, last_success, age, agent, now) do
    cond do
      not connected -> :reconnecting
      is_nil(last_attempt) -> :unknown
      rate_limited?(last_attempt) -> :delayed
      last_attempt.kind == "sync_error" -> :offline
      is_nil(last_success) -> :unknown
      true -> healthy_state(age, agent, now, last_success)
    end
  end

  defp healthy_state(age, agent, now, last_success) do
    cond do
      age > @stale_ttl -> :offline
      age > @github_ttl -> :delayed
      errors(last_success) > 0 -> :delayed
      not agent.ok -> :delayed
      running_without_heartbeat?(now, agent) -> :delayed
      true -> :live
    end
  end

  defp running_without_heartbeat?(now, %{ok: true, at: at, tickets: tickets}) do
    running? = Enum.any?(tickets, &(&1["assignment"] == "running" and is_nil(&1["idle_at"])))
    age = age_sec(now, at)
    running? and is_integer(age) and age > @agent_running_ttl
  end

  defp running_without_heartbeat?(_now, _agent), do: false

  defp sources(now, state, last_attempt, last_success, age, agent) do
    [
      github_source(now, state, last_attempt, last_success, age),
      agent_source(now, agent),
      %{
        code: :queue_current,
        kind: :run,
        age_sec: 0
      }
    ]
  end

  defp github_source(_now, state, last_attempt, last_success, age) do
    cond do
      is_nil(last_attempt) ->
        %{
          code: :github_waiting,
          kind: :unknown,
          age_sec: nil
        }

      rate_limited?(last_attempt) ->
        %{
          code: :github_rate_limited,
          retry_after: last_attempt.payload["retry_after"],
          kind: :stale,
          age_sec: age
        }

      last_attempt.kind == "sync_error" ->
        %{
          code: :github_failed,
          attempted_at: last_attempt.inserted_at,
          kind: :blocked,
          age_sec: age
        }

      state == :delayed and errors(last_success) > 0 ->
        %{
          code: :github_errors,
          error_count: errors(last_success),
          kind: :stale,
          age_sec: age
        }

      state == :delayed ->
        %{
          code: :github_delayed,
          kind: :stale,
          age_sec: age
        }

      true ->
        %{
          code: :github_current,
          kind: :run,
          age_sec: age
        }
    end
  end

  # A limit that lifts by itself is a delay, not a lost connection: the board
  # waits and retries, and nothing is wrong on the owner's side.
  defp rate_limited?(%{kind: "sync_error", payload: %{"rate_limited" => true}}), do: true
  defp rate_limited?(_event), do: false

  defp errors(nil), do: 0
  defp errors(%{payload: %{"errors" => n}}) when is_integer(n), do: n
  defp errors(_event), do: 0

  defp agent_source(_now, %{ok: false}), do: agent_unavailable()

  defp agent_source(now, %{ok: true, at: at, tickets: tickets}) do
    age = age_sec(now, at)
    running? = Enum.any?(tickets, &(&1["assignment"] == "running" and is_nil(&1["idle_at"])))

    cond do
      running? and is_integer(age) and age > @agent_running_ttl ->
        %{
          code: :agent_stale,
          kind: :stale,
          age_sec: age
        }

      is_nil(at) ->
        %{
          code: :agent_empty,
          kind: :run,
          age_sec: 0
        }

      true ->
        %{
          code: :agent_current,
          kind: :run,
          age_sec: 0
        }
    end
  end

  defp agent_unavailable do
    %{
      code: :agent_unavailable,
      kind: :blocked,
      age_sec: nil
    }
  end

  defp age_sec(_now, nil), do: nil

  defp age_sec(now, at) when is_struct(at, DateTime) do
    max(DateTime.diff(now, at, :second), 0)
  end

  defp age_sec(_now, _at), do: nil
end
