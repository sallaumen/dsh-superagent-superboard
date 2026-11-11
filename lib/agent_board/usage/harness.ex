defmodule AgentBoard.Usage.Harness do
  @moduledoc """
  What the DeepSeek Harness spent on a task, read from the harness's
  own transcripts.

  The DeepSeek Harness keeps one zstd-compressed JSONL transcript per session
  under `~/.dsh/sessions/<encoded ticket directory>/<session>/`: the worker
  (`worker-<ticket id>`, delegation depth 0) and the subagents it started
  (depth 1). Every `assistant/message` event carries the model's usage in
  `data.usage` (`inputTokens`, `outputTokens`, `cacheReadTokens`,
  `cacheWriteTokens`; input excludes cache reads) and its id in
  `data.message.id`, and a `model/selection` or `request/context` event
  names the model (a subagent's transcript has only the second).

  The tokens are measured. The cost is an estimate from the board's price
  table (`AgentBoard.AI.Providers`): a token kind with no price makes the
  total a minimum, and a model with no price at all makes it unknown, never
  zero. The board only reads these files; it never writes them.
  """

  alias AgentBoard.AI.Providers
  alias AgentBoard.Usage.Fields

  @transcript "session.v4.jsonl.zstd"
  @strings MapSet.new(~w(type id model cwd))

  @type cost :: %{micros: non_neg_integer(), complete?: boolean()} | nil
  @type message :: %{
          key: String.t() | integer(),
          at: DateTime.t() | nil,
          model: String.t() | nil,
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer()
        }
  @type transcript :: %{
          messages: [message()],
          model: String.t() | nil,
          subagent?: boolean(),
          cwd: String.t() | nil
        }
  @type session :: %{
          requests: non_neg_integer(),
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer(),
          model: String.t() | nil,
          subagent?: boolean(),
          peak: %{
            input: non_neg_integer(),
            output: non_neg_integer(),
            cache_read: non_neg_integer()
          },
          timed?: boolean(),
          parts: [map()] | nil
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
    transcript = read_transcript(jsonl)
    messages = Enum.filter(transcript.messages, &in_window?(&1, Keyword.get(opts, :window)))

    models =
      messages
      |> Enum.map(& &1.model)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # A session that switched models has no one model: `parts` keeps each
    # model's tokens, so each pays its own price, as in the ledger.
    model =
      case models do
        [] -> transcript.model
        [one] -> one
        _many -> nil
      end

    messages
    |> totals()
    |> Map.merge(%{
      requests: length(messages),
      model: model,
      subagent?: transcript.subagent?,
      parts: parts(messages, models)
    })
  end

  defp totals(messages) do
    sum = fn key -> messages |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum() end

    %{
      input: sum.(:input),
      output: sum.(:output),
      cache_read: sum.(:cache_read),
      cache_write: sum.(:cache_write),
      peak: peak_tokens(messages),
      timed?: Enum.all?(messages, & &1.at)
    }
  end

  defp parts(_messages, models) when length(models) < 2, do: nil

  defp parts(messages, _models) do
    messages
    |> Enum.group_by(& &1.model)
    |> Enum.map(fn {model, mine} -> mine |> totals() |> Map.put(:model, model) end)
  end

  # The tokens of the messages sent in the provider's peak hours.
  defp peak_tokens(messages) do
    peak = Enum.filter(messages, &(&1.at && Providers.peak?(&1.at)))
    sum = fn key -> peak |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum() end
    %{input: sum.(:input), output: sum.(:output), cache_read: sum.(:cache_read)}
  end

  @doc """
  One transcript's messages, each once (by `data.message.id`, else `seq`),
  with the time of the event, the model selected before it, and the
  session's cwd and depth. `parse/1` sums these; the usage ledger
  (`AgentBoard.Usage.Ledger`) stores them per day. Lines go through
  `AgentBoard.Usage.Fields`: numbers and named metadata only.
  """
  @spec read_transcript(binary()) :: transcript()
  def read_transcript(jsonl) do
    acc = %{messages: [], model: nil, subagent?: false, cwd: nil, seen: MapSet.new()}

    jsonl
    |> String.split("\n", trim: true)
    |> Enum.reduce(acc, fn line, acc ->
      case Fields.decode(line, @strings) do
        {:ok, event} -> take(event, acc)
        :error -> acc
      end
    end)
    |> then(fn acc ->
      %{
        messages: Enum.reverse(acc.messages),
        model: acc.model,
        subagent?: acc.subagent?,
        cwd: acc.cwd
      }
    end)
  end

  @doc """
  One session transcript from disk. `{:error, :zstd_missing}` without
  `zstd` on the PATH, `{:error, :unreadable}` when it cannot decompress it.
  """
  @spec read_file(String.t()) :: {:ok, transcript()} | {:error, :zstd_missing | :unreadable}
  def read_file(path) do
    if System.find_executable("zstd") do
      case decompress(path) do
        {:ok, jsonl} -> {:ok, read_transcript(jsonl)}
        :error -> {:error, :unreadable}
      end
    else
      {:error, :zstd_missing}
    end
  end

  @doc """
  The estimated cost of these sessions, in microdollars, from the board's
  price table, each token at the rate of its hour. `complete?` is false when
  a token kind or a model had no price, or a message has no time (it is then
  priced off-peak); nil when no session's model has a price.
  """
  @spec cost([map()]) :: cost()
  def cost(sessions) do
    priced =
      sessions
      |> Enum.flat_map(&priced_parts/1)
      |> Enum.map(&{&1, Providers.prices_for_model(&1.model)})

    if Enum.all?(priced, fn {_session, prices} -> is_nil(prices) end) do
      nil
    else
      Enum.reduce(priced, %{micros: 0, complete?: true}, fn
        {_session, nil}, acc -> %{acc | complete?: false}
        {session, prices}, acc -> add_cost(acc, session, prices)
      end)
    end
  end

  defp priced_parts(session), do: Map.get(session, :parts) || [session]

  defp add_cost(acc, session, prices) do
    peak = Map.get(session, :peak, %{input: 0, output: 0, cache_read: 0})
    timed? = is_nil(prices[:off_peak]) or Map.get(session, :timed?, false)
    read = Providers.at_full_rate(session.cache_read, peak.cache_read, prices)
    {cache_read, read_known?} = priced(read, prices[:cache_read])
    {cache_write, write_known?} = priced(session.cache_write, prices[:cache_write])

    micros =
      round(
        Providers.at_full_rate(session.input, peak.input, prices) * prices.input +
          Providers.at_full_rate(session.output, peak.output, prices) * prices.output
      ) + cache_read + cache_write

    %{
      micros: acc.micros + micros,
      complete?: acc.complete? and timed? and read_known? and write_known?
    }
  end

  defp priced(tokens, _price) when tokens == 0, do: {0, true}
  defp priced(_tokens, nil), do: {0, false}
  defp priced(tokens, price), do: {round(tokens * price), true}

  defp in_window?(_message, nil), do: true
  defp in_window?(%{at: nil}, _window), do: false

  defp in_window?(%{at: at}, {from, until}) do
    ms = DateTime.to_unix(at, :millisecond)
    ms >= from and ms < until
  end

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
          sessions
          |> Enum.flat_map(&priced_parts/1)
          |> Enum.map(& &1.model)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort(),
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
    do: %{acc | subagent?: (event["delegationDepth"] || 0) > 0, cwd: event["cwd"]}

  # A subagent's transcript has no `model/selection`: the model is named in
  # each request's `request/context`.
  defp take(%{"type" => type, "data" => %{"model" => model}}, acc)
       when type in ["model/selection", "request/context"] and is_binary(model),
       do: %{acc | model: model}

  defp take(%{"type" => "assistant/message", "data" => %{"usage" => usage} = data} = event, acc)
       when is_map(usage) do
    key = get_in(data, ["message", "id"]) || event["seq"]

    if key != nil and MapSet.member?(acc.seen, key) do
      acc
    else
      message = %{
        key: key,
        at: time(event["time"]),
        model: acc.model,
        input: count(usage["inputTokens"]),
        output: count(usage["outputTokens"]),
        cache_read: count(usage["cacheReadTokens"]),
        cache_write: count(usage["cacheWriteTokens"])
      }

      %{
        acc
        | messages: [message | acc.messages],
          seen: if(key, do: MapSet.put(acc.seen, key), else: acc.seen)
      }
    end
  end

  defp take(_event, acc), do: acc

  defp time(ms) when is_integer(ms) and ms > 0, do: DateTime.from_unix!(ms, :millisecond)
  defp time(_ms), do: nil

  defp count(n) when is_integer(n) and n > 0, do: n
  defp count(_), do: 0
end
