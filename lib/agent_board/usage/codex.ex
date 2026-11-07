defmodule AgentBoard.Usage.Codex do
  @moduledoc """
  What Codex spent, read from its local state.

  Codex keeps one row per thread in `~/.codex/state_5.sqlite`, table
  `threads` (`:codex_state_db`), and one rollout per thread under
  `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<thread id>.jsonl`
  (`:codex_sessions_dir`); older rollouts are zstd-compressed (`.jsonl.zst`)
  while `threads.rollout_path` still names the `.jsonl`.

  Counting rules, observed on 2026-11-07 (`docs/research/alfred.md` §3.3):

    * Every `event_msg` of type `token_count` with `info` carries the
      thread's **cumulative** `total_token_usage`. The thread's total is the
      last one (it equals `threads.tokens_used`); a day's usage is the
      difference between consecutive totals, credited to the day of the
      later event. A total that goes down starts a new count.
    * `input_tokens` includes the cached input (`cached_input_tokens`) and
      `output_tokens` includes reasoning; `total_tokens = input + output`.
      `last_token_usage` repeats and is never summed.
    * The last `rate_limits` read is the plan's quota: the share of each
      window used (`used_percent`, `window_minutes`, `resets_at`), the plan
      and the credits.

  The tokens are measured. Codex runs on the owner's ChatGPT plan: there is
  no dollar amount anywhere, only the share of the weekly window used.

  The `threads` query names its columns: `title`, `preview`, `name` and
  `first_user_message` hold conversation text and are never read. Rollout
  lines go through `AgentBoard.Usage.Fields`, which keeps numbers and named
  metadata only. The board never writes these files.
  """

  alias AgentBoard.Usage.{Fields, Lines}

  @columns ~w(id rollout_path created_at updated_at source thread_source originator
              model_provider model reasoning_effort cwd git_branch git_sha git_origin_url
              cli_version tokens_used archived)a
  @counts [:input, :cached_input, :cache_write, :output, :reasoning, :total]
  @strings MapSet.new(~w(type timestamp limit_id plan_type rate_limit_reached_type balance))
  @thread_id ~r/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl(?:\.zst)?$/

  @typedoc """
  Codex's own counts: `input` includes `cached_input`, `output` includes
  `reasoning`, and `total = input + output`.
  """
  @type usage :: %{
          input: non_neg_integer(),
          cached_input: non_neg_integer(),
          cache_write: non_neg_integer(),
          output: non_neg_integer(),
          reasoning: non_neg_integer(),
          total: non_neg_integer()
        }

  @typedoc "The usage credited to one UTC day; `requests` counts the totals that grew."
  @type day :: %{
          day: Date.t(),
          requests: pos_integer(),
          first_at: DateTime.t(),
          last_at: DateTime.t(),
          input: non_neg_integer(),
          cached_input: non_neg_integer(),
          cache_write: non_neg_integer(),
          output: non_neg_integer(),
          reasoning: non_neg_integer(),
          total: non_neg_integer()
        }

  @type thread :: %{
          id: String.t(),
          rollout_path: String.t() | nil,
          created_at: integer() | nil,
          updated_at: integer() | nil,
          source: String.t() | nil,
          thread_source: String.t() | nil,
          originator: String.t() | nil,
          model_provider: String.t() | nil,
          model: String.t() | nil,
          reasoning_effort: String.t() | nil,
          cwd: String.t() | nil,
          git_branch: String.t() | nil,
          git_sha: String.t() | nil,
          git_origin_url: String.t() | nil,
          cli_version: String.t() | nil,
          tokens_used: integer() | nil,
          archived: boolean()
        }

  @type rate_limits :: %{
          observed_at: DateTime.t(),
          limit_id: String.t() | nil,
          plan_type: String.t() | nil,
          primary: window() | nil,
          secondary: window() | nil,
          credits:
            %{has_credits: boolean() | nil, unlimited: boolean() | nil, balance: String.t() | nil}
            | nil,
          reached: String.t() | nil
        }

  @type window :: %{
          used_percent: number() | nil,
          window_minutes: non_neg_integer() | nil,
          resets_at: DateTime.t() | nil
        }

  @type rollout :: %{
          thread_id: String.t() | nil,
          total: usage() | nil,
          days: [day()],
          rate_limits: rate_limits() | nil,
          skipped: non_neg_integer()
        }

  @doc "The `threads` columns this reader selects, by name."
  @spec columns() :: [atom()]
  def columns, do: @columns

  @doc "The only keys whose string values this reader keeps from a rollout line."
  @spec string_fields() :: [String.t()]
  def string_fields, do: @strings |> MapSet.to_list() |> Enum.sort()

  @doc "Codex's thread database (`:codex_state_db`)."
  @spec state_db() :: String.t()
  def state_db do
    Application.get_env(:agent_board, :codex_state_db) || Path.expand("~/.codex/state_5.sqlite")
  end

  @doc "Where Codex keeps its rollouts (`:codex_sessions_dir`)."
  @spec sessions_dir() :: String.t()
  def sessions_dir do
    Application.get_env(:agent_board, :codex_sessions_dir) || Path.expand("~/.codex/sessions")
  end

  @doc "Every rollout under `dir`, plain or zstd, sorted."
  @spec rollouts(String.t()) :: [String.t()]
  def rollouts(dir \\ sessions_dir()) do
    ["**/rollout-*.jsonl", "**/rollout-*.jsonl.zst"]
    |> Enum.flat_map(&Path.wildcard(Path.join(dir, &1)))
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end

  @doc "The thread id in a rollout's file name, or nil."
  @spec thread_id(String.t()) :: String.t() | nil
  def thread_id(path) do
    case Regex.run(@thread_id, Path.basename(path)) do
      [_, id] -> id
      nil -> nil
    end
  end

  @doc """
  Every thread, read-only, with the columns in `columns/0` and nothing
  else. `{:error, reason}` when the database is absent or unreadable.
  """
  @spec threads(String.t()) :: {:ok, [thread()]} | {:error, term()}
  def threads(db \\ state_db()) do
    if File.regular?(db), do: query_threads(db), else: {:error, :enoent}
  end

  defp query_threads(db) do
    with {:ok, conn} <- Exqlite.Sqlite3.open(db, mode: :readonly) do
      try do
        :ok = Exqlite.Sqlite3.set_busy_timeout(conn, 2_000)
        sql = "SELECT #{Enum.map_join(@columns, ", ", &Atom.to_string/1)} FROM threads"

        with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql),
             {:ok, rows} <- Exqlite.Sqlite3.fetch_all(conn, stmt) do
          Exqlite.Sqlite3.release(conn, stmt)
          {:ok, Enum.map(rows, &thread/1)}
        end
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  defp thread(row) do
    @columns
    |> Enum.zip(row)
    |> Map.new()
    |> Map.update!(:archived, &(&1 == 1))
  end

  @doc """
  One rollout: its thread's last cumulative total, the usage credited to
  each UTC day, the last `rate_limits` and how many candidate lines could
  not be read.
  """
  @spec read_rollout(String.t()) :: {:ok, rollout()} | {:error, term()}
  def read_rollout(path) do
    acc = %{previous: nil, days: %{}, rate_limits: nil, skipped: 0}

    with {:ok, acc} <- Lines.reduce(path, acc, &take_line/2) do
      {:ok,
       %{
         thread_id: thread_id(path),
         total: acc.previous,
         days: acc.days |> Map.values() |> Enum.sort_by(& &1.day, Date),
         rate_limits: acc.rate_limits,
         skipped: acc.skipped
       }}
    end
  end

  defp take_line(line, acc) do
    if :binary.match(line, ~s("token_count")) == :nomatch do
      acc
    else
      case Fields.decode(line, @strings) do
        {:ok, %{"payload" => %{"type" => "token_count"} = payload} = event} ->
          take_token_count(payload, time(event["timestamp"]), acc)

        {:ok, _other} ->
          acc

        :error ->
          %{acc | skipped: acc.skipped + 1}
      end
    end
  end

  defp take_token_count(_payload, :error, acc), do: %{acc | skipped: acc.skipped + 1}

  defp take_token_count(payload, {:ok, at}, acc) do
    acc
    |> take_total(get_in(payload, ["info", "total_token_usage"]), at)
    |> take_rate_limits(payload["rate_limits"], at)
  end

  defp take_total(acc, total, at) when is_map(total) do
    total = usage(total)
    delta = delta(acc.previous, total)
    %{acc | previous: total, days: credit(acc.days, at, delta)}
  end

  defp take_total(acc, _total, _at), do: acc

  # A total below the previous one is a new count, not a negative usage.
  defp delta(nil, total), do: total

  defp delta(previous, total) do
    if total.total < previous.total do
      total
    else
      Map.new(total, fn {key, value} -> {key, max(value - Map.fetch!(previous, key), 0)} end)
    end
  end

  defp credit(days, _at, %{total: 0}), do: days

  defp credit(days, at, delta) do
    day = DateTime.to_date(at)

    empty =
      Map.merge(%{day: day, requests: 0, first_at: at, last_at: at}, Map.new(@counts, &{&1, 0}))

    entry =
      Enum.reduce(@counts, Map.get(days, day, empty), fn key, entry ->
        Map.update!(entry, key, &(&1 + Map.fetch!(delta, key)))
      end)

    Map.put(days, day, %{entry | requests: entry.requests + 1, last_at: at})
  end

  defp usage(total) do
    %{
      input: count(total["input_tokens"]),
      cached_input: count(total["cached_input_tokens"]),
      cache_write: count(total["cache_write_input_tokens"]),
      output: count(total["output_tokens"]),
      reasoning: count(total["reasoning_output_tokens"]),
      total: count(total["total_tokens"])
    }
  end

  defp take_rate_limits(acc, limits, at) when is_map(limits) do
    %{
      acc
      | rate_limits: %{
          observed_at: at,
          limit_id: limits["limit_id"],
          plan_type: limits["plan_type"],
          primary: window(limits["primary"]),
          secondary: window(limits["secondary"]),
          credits: credits(limits["credits"]),
          reached: limits["rate_limit_reached_type"]
        }
    }
  end

  defp take_rate_limits(acc, _limits, _at), do: acc

  defp window(%{} = window) do
    %{
      used_percent: number(window["used_percent"]),
      window_minutes: if(is_integer(window["window_minutes"]), do: window["window_minutes"]),
      resets_at:
        case window["resets_at"] do
          seconds when is_integer(seconds) -> DateTime.from_unix!(seconds)
          _ -> nil
        end
    }
  end

  defp window(_window), do: nil

  defp credits(%{} = credits) do
    %{
      has_credits: boolean(credits["has_credits"]),
      unlimited: boolean(credits["unlimited"]),
      balance: credits["balance"]
    }
  end

  defp credits(_credits), do: nil

  defp time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _ -> :error
    end
  end

  defp time(_value), do: :error

  defp count(n) when is_integer(n) and n > 0, do: n
  defp count(_), do: 0

  defp number(n) when is_number(n), do: n
  defp number(_), do: nil

  defp boolean(b) when is_boolean(b), do: b
  defp boolean(_), do: nil
end
