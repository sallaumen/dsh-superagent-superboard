defmodule AgentBoard.ExecutorUsage do
  @moduledoc """
  What the coding agent's executor spent on a task, read from the harness's
  own transcripts.

  The DeepSeek Harness keeps one zstd-compressed JSONL transcript per session
  under `~/.dsh/sessions/<encoded ticket directory>/<session>/`: the worker
  (`worker-<ticket id>`, delegation depth 0) and the subagents it started
  (depth 1). Every `assistant/message` event carries the model's usage in
  `data.usage` (`inputTokens`, `outputTokens`, `cacheReadTokens`,
  `cacheWriteTokens`; input excludes cache reads) and its id in
  `data.message.id`, and a `model/selection` event names the model.

  The tokens are measured. The cost is an estimate from the board's price
  table (`AgentBoard.AI.Providers`): a token kind with no price makes the
  total a minimum, and a model with no price at all makes it unknown, never
  zero. The board only reads these files; it never writes them.
  """

  alias AgentBoard.AI.Providers

  @transcript "session.v4.jsonl.zstd"

  @type cost :: %{micros: non_neg_integer(), complete?: boolean()} | nil
  @type session :: %{
          requests: non_neg_integer(),
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer(),
          model: String.t() | nil,
          subagent?: boolean()
        }
  @type t :: %{
          status: :measured | :none | :unavailable,
          reason: atom() | nil,
          signature: list(),
          workers: non_neg_integer(),
          subagents: non_neg_integer(),
          unreadable: non_neg_integer(),
          requests: non_neg_integer(),
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer(),
          models: [String.t()],
          cost: cost()
        }

  @doc "Where the harness keeps its session transcripts (`:dsh_sessions_dir`)."
  @spec sessions_dir() :: String.t()
  def sessions_dir do
    Application.get_env(:agent_board, :dsh_sessions_dir) || Path.expand("~/.dsh/sessions")
  end

  @doc """
  The harness's folder for a ticket directory: every `/` becomes `-`, with
  `--` around it (observed in `~/.dsh/sessions`, not documented by the
  harness).
  """
  @spec transcript_dir(String.t()) :: String.t()
  def transcript_dir(directory) do
    Path.join(sessions_dir(), "-" <> String.replace(directory, "/", "-") <> "--")
  end

  @doc """
  The usage of every session of these tickets (a task's tickets share its
  issue number). `previous` is the last reading: when no transcript changed
  (same files, sizes and modification times) it is returned as is, so a
  board update does not decompress the files again.
  """
  @spec for_tickets([map()], t() | nil) :: t()
  def for_tickets(tickets, previous \\ nil) do
    files =
      tickets
      |> Enum.map(&get_in(&1, ["execution", "directory"]))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.flat_map(&transcripts/1)

    signature = Enum.map(files, &{&1, stamp(&1)})

    cond do
      files == [] -> empty(:none, nil, [])
      match?(%{signature: ^signature}, previous) -> previous
      true -> read(files, signature)
    end
  end

  @doc """
  Everything the harness spent between two instants: every session
  transcript under `sessions_dir/0` changed since `since` (the workers, their
  subagents and the orchestrator), counting only the messages whose `time`
  falls in `[since, until)`. The summary of the day reads it once a day; a
  board render never does.
  """
  @spec window(DateTime.t(), DateTime.t()) :: t()
  def window(%DateTime{} = since, %DateTime{} = until) do
    from = DateTime.to_unix(since)

    files =
      [sessions_dir(), "*", "*", @transcript]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.filter(&changed_since?(&1, from))
      |> Enum.sort()

    signature = Enum.map(files, &{&1, stamp(&1)})
    bounds = {DateTime.to_unix(since, :millisecond), DateTime.to_unix(until, :millisecond)}

    if files == [], do: empty(:none, nil, []), else: read(files, signature, window: bounds)
  end

  defp changed_since?(file, from) do
    case File.stat(file, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime >= from
      {:error, _} -> false
    end
  end

  @doc """
  One transcript's usage. Malformed lines are skipped; each message counts
  once. With `window: {from_ms, until_ms}` only the messages whose `time`
  falls in `[from_ms, until_ms)` count; a message without a time does not.
  """
  @spec parse(binary(), keyword()) :: session()
  def parse(jsonl, opts \\ []) do
    window = Keyword.get(opts, :window)

    acc = %{
      requests: 0,
      input: 0,
      output: 0,
      cache_read: 0,
      cache_write: 0,
      model: nil,
      subagent?: false,
      seen: MapSet.new()
    }

    jsonl
    |> String.split("\n", trim: true)
    |> Enum.reduce(acc, fn line, acc ->
      case Jason.decode(line) do
        {:ok, event} when is_map(event) ->
          if counted?(event, window), do: take(event, acc), else: acc

        _ ->
          acc
      end
    end)
    |> Map.delete(:seen)
  end

  @doc """
  The estimated cost of these sessions, in microdollars, from the board's
  price table. `complete?` is false when a token kind or a model had no
  price; nil when no session's model has a price.
  """
  @spec cost([map()]) :: cost()
  def cost(sessions) do
    priced = Enum.map(sessions, &{&1, Providers.prices_for_model(&1.model)})

    if Enum.all?(priced, fn {_session, prices} -> is_nil(prices) end) do
      nil
    else
      Enum.reduce(priced, %{micros: 0, complete?: true}, fn
        {_session, nil}, acc -> %{acc | complete?: false}
        {session, prices}, acc -> add_cost(acc, session, prices)
      end)
    end
  end

  defp add_cost(acc, session, prices) do
    {cache_read, read_known?} = priced(session.cache_read, prices[:cache_read])
    {cache_write, write_known?} = priced(session.cache_write, prices[:cache_write])

    micros =
      round(session.input * prices.input + session.output * prices.output) + cache_read +
        cache_write

    %{micros: acc.micros + micros, complete?: acc.complete? and read_known? and write_known?}
  end

  defp priced(0, _price), do: {0, true}
  defp priced(_tokens, nil), do: {0, false}
  defp priced(tokens, price), do: {round(tokens * price), true}

  defp counted?(_event, nil), do: true

  defp counted?(%{"type" => "assistant/message", "time" => t}, {from, until}) when is_integer(t),
    do: t >= from and t < until

  defp counted?(%{"type" => "assistant/message"}, _window), do: false
  defp counted?(_event, _window), do: true

  defp transcripts(directory) do
    folder = transcript_dir(directory)

    case File.ls(folder) do
      {:ok, sessions} ->
        sessions
        |> Enum.map(&Path.join([folder, &1, @transcript]))
        |> Enum.filter(&File.regular?/1)
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  defp stamp(file) do
    case File.stat(file) do
      {:ok, %{size: size, mtime: mtime}} -> {size, mtime}
      {:error, _} -> nil
    end
  end

  # `zstd` comes from the PATH; the launchd service's PATH includes Homebrew
  # (`ops/com.agentboard.plist`).
  defp read(files, signature, opts \\ []) do
    if System.find_executable("zstd") do
      {sessions, unreadable} = Enum.reduce(files, {[], 0}, &read_one(&1, &2, opts))
      sessions = if opts[:window], do: Enum.filter(sessions, &(&1.requests > 0)), else: sessions
      summarize(sessions, unreadable, signature)
    else
      empty(:unavailable, :zstd_missing, signature)
    end
  end

  defp read_one(file, {sessions, unreadable}, opts) do
    case decompress(file) do
      {:ok, jsonl} -> {[parse(jsonl, window: opts[:window]) | sessions], unreadable}
      :error -> {sessions, unreadable + 1}
    end
  end

  defp decompress(file) do
    case System.cmd("zstd", ["-dcq", "--", file], stderr_to_stdout: false) do
      {jsonl, 0} -> {:ok, jsonl}
      _ -> :error
    end
  end

  defp summarize(sessions, unreadable, signature) do
    sum = fn key -> sessions |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum() end

    %{
      empty(:measured, nil, signature)
      | workers: Enum.count(sessions, &(not &1.subagent?)),
        subagents: Enum.count(sessions, & &1.subagent?),
        unreadable: unreadable,
        requests: sum.(:requests),
        input: sum.(:input),
        output: sum.(:output),
        cache_read: sum.(:cache_read),
        cache_write: sum.(:cache_write),
        models:
          sessions |> Enum.map(& &1.model) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort(),
        cost: cost(sessions)
    }
  end

  defp empty(status, reason, signature) do
    %{
      status: status,
      reason: reason,
      signature: signature,
      workers: 0,
      subagents: 0,
      unreadable: 0,
      requests: 0,
      input: 0,
      output: 0,
      cache_read: 0,
      cache_write: 0,
      models: [],
      cost: nil
    }
  end

  defp take(%{"type" => "session"} = event, acc),
    do: %{acc | subagent?: (event["delegationDepth"] || 0) > 0}

  defp take(%{"type" => "model/selection", "data" => %{"model" => model}}, acc)
       when is_binary(model),
       do: %{acc | model: model}

  defp take(%{"type" => "assistant/message", "data" => %{"usage" => usage} = data} = event, acc)
       when is_map(usage) do
    key = get_in(data, ["message", "id"]) || event["seq"]

    if key != nil and MapSet.member?(acc.seen, key) do
      acc
    else
      %{
        acc
        | requests: acc.requests + 1,
          input: acc.input + count(usage["inputTokens"]),
          output: acc.output + count(usage["outputTokens"]),
          cache_read: acc.cache_read + count(usage["cacheReadTokens"]),
          cache_write: acc.cache_write + count(usage["cacheWriteTokens"]),
          seen: if(key, do: MapSet.put(acc.seen, key), else: acc.seen)
      }
    end
  end

  defp take(_event, acc), do: acc

  defp count(n) when is_integer(n) and n > 0, do: n
  defp count(_), do: 0
end
