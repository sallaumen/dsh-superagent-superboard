defmodule AgentBoard.Usage.ClaudeCode do
  @moduledoc """
  What Claude Code spent, read from its own transcripts.

  Claude Code writes one JSONL file per session under
  `~/.claude/projects/<encoded cwd>/<session>.jsonl` (`:claude_projects_dir`),
  and one per subagent under `<session>/subagents/agent-<id>.jsonl`. Every
  `assistant` line carries `message.id`, `message.model` and
  `message.usage`, plus `sessionId`, `cwd`, `gitBranch` and `timestamp`.

  Counting rules, observed on 2026-11-07 (`docs/research/alfred.md` §3.3):

    * Only `assistant` lines count, and never `model == "<synthetic>"`.
    * **One message per `message.id` across every file.** Each content block
      of a message is its own line, and a forked or moved session copies the
      parent's lines into another file. Older CLIs (2.1.237–2.1.299) wrote a
      partial `output_tokens` on the earlier blocks, so two copies merge by
      the largest value of each count.
    * A copy keeps the session, cwd and branch of the first copy read.
    * `input_tokens` excludes the cache; `cache_creation_input_tokens` is
      the cache write and `cache_read_input_tokens` the cache read;
      `output_tokens` includes thinking.

  The tokens are measured. Claude Code runs on the owner's Claude Max
  subscription, so there is no bill per token here: the `cost-state` lines
  carry Claude Code's own list-price estimate per process (`totalCostUSD`),
  which `cost_states/1` reads to reconcile the counts, never as a charge.
  `pr_links/1` reads the `pr-link` lines (repository and number), what
  `AgentBoard.Attribution.for_session/2` needs to tie a session to a task.

  Only numbers and named metadata are read (`AgentBoard.Usage.Fields`): no
  message content, title or prompt reaches this module. The board never
  writes these files.
  """

  alias AgentBoard.Usage.Fields

  @strings MapSet.new(~w(type id model sessionId cwd gitBranch timestamp prRepository))
  @wanted [~s("type":"assistant"), ~s("type":"cost-state"), ~s("type":"pr-link")]

  @type message :: %{
          id: String.t(),
          session_id: String.t() | nil,
          at: DateTime.t(),
          cwd: String.t() | nil,
          git_branch: String.t() | nil,
          model: String.t() | nil,
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer()
        }

  @type group :: %{
          session_id: String.t() | nil,
          day: Date.t(),
          cwd: String.t() | nil,
          git_branch: String.t() | nil,
          model: String.t() | nil,
          requests: pos_integer(),
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer(),
          first_at: DateTime.t(),
          last_at: DateTime.t()
        }

  @type cost_state :: %{
          session_id: String.t(),
          start_time: integer() | nil,
          cost_usd: number() | nil,
          models: %{
            optional(String.t()) => %{
              input: non_neg_integer(),
              output: non_neg_integer(),
              cache_read: non_neg_integer(),
              cache_write: non_neg_integer(),
              cost_usd: number() | nil
            }
          }
        }

  @type pr_link :: %{session_id: String.t(), repository: String.t(), number: pos_integer()}

  @type file :: %{
          messages: [message()],
          cost_states: [cost_state()],
          pr_links: [pr_link()],
          skipped: non_neg_integer(),
          offset: non_neg_integer()
        }

  @doc "The only keys whose string values this reader keeps; every other string is dropped."
  @spec string_fields() :: [String.t()]
  def string_fields, do: @strings |> MapSet.to_list() |> Enum.sort()

  @doc "Where Claude Code keeps its transcripts (`:claude_projects_dir`)."
  @spec projects_dir() :: String.t()
  def projects_dir do
    Application.get_env(:agent_board, :claude_projects_dir) || Path.expand("~/.claude/projects")
  end

  @doc "Every transcript under `dir`: sessions, subagents and workflow agents, sorted."
  @spec transcripts(String.t()) :: [String.t()]
  def transcripts(dir \\ projects_dir()) do
    dir
    |> Path.join("**/*.jsonl")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end

  @doc """
  One transcript, read line by line: its messages (each `message.id`
  once), its `cost-state` snapshots, the PRs it linked (`pr-link` lines) and
  how many candidate lines could not be read. A line that is not JSON, or an
  assistant line without an id or a timestamp, is skipped and counted.

  `from:` starts at a byte offset (a transcript only grows, so a reader can
  continue where it stopped). `offset` is where the next read should start:
  the end of the last complete line, so a line still being written is read
  again, whole, next time.
  """
  @spec read_file(String.t(), keyword()) :: {:ok, file()} | {:error, File.posix() | term()}
  def read_file(path, opts \\ []) do
    from = Keyword.get(opts, :from, 0)
    acc = %{messages: %{}, order: [], cost_states: [], pr_links: [], skipped: 0, offset: from}

    with {:ok, fd} <- :file.open(path, [:read, :raw, :binary, {:read_ahead, 65_536}]) do
      try do
        with {:ok, _position} <- :file.position(fd, from),
             {:ok, acc} <- read_lines(fd, acc) do
          {:ok,
           %{
             messages: acc.order |> Enum.reverse() |> Enum.map(&Map.fetch!(acc.messages, &1)),
             cost_states: Enum.reverse(acc.cost_states),
             pr_links: acc.pr_links |> Enum.reverse() |> Enum.uniq(),
             skipped: acc.skipped,
             offset: acc.offset
           }}
        end
      after
        :file.close(fd)
      end
    end
  end

  defp read_lines(fd, acc) do
    case :file.read_line(fd) do
      {:ok, line} ->
        if :binary.last(line) == ?\n do
          read_lines(fd, %{take_line(line, acc) | offset: acc.offset + byte_size(line)})
        else
          # The last line has no newline yet: count it if it is whole, but
          # leave the offset before it.
          {:ok, take_line(line, acc)}
        end

      :eof ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The messages of these transcripts, each `message.id` once across all of
  them. Files are read in the given order, and the first copy of a message
  names its session; the counts merge by `merge/2`. Unreadable files are
  skipped.
  """
  @spec messages([String.t()]) :: [message()]
  def messages(paths) do
    {by_id, order} =
      Enum.reduce(paths, {%{}, []}, fn path, acc ->
        case read_file(path) do
          {:ok, %{messages: messages}} -> Enum.reduce(messages, acc, &add_message/2)
          {:error, _reason} -> acc
        end
      end)

    order |> Enum.reverse() |> Enum.map(&Map.fetch!(by_id, &1))
  end

  @doc """
  Two copies of the same message as one: the first copy's session, time,
  cwd, branch and model, and the largest value of each count (an earlier
  content block of an older CLI carries a partial `output_tokens`).
  """
  @spec merge(message(), message()) :: message()
  def merge(first, other) do
    %{
      first
      | input: max(first.input, other.input),
        output: max(first.output, other.output),
        cache_read: max(first.cache_read, other.cache_read),
        cache_write: max(first.cache_write, other.cache_write)
    }
  end

  @doc """
  The messages grouped by session, UTC day, cwd, branch and model, with the
  number of messages (`requests`) and the summed tokens.
  """
  @spec groups([message()]) :: [group()]
  def groups(messages) do
    messages
    |> Enum.group_by(&{&1.session_id, DateTime.to_date(&1.at), &1.cwd, &1.git_branch, &1.model})
    |> Enum.map(fn {{session_id, day, cwd, branch, model}, members} ->
      times = Enum.map(members, & &1.at)

      %{
        session_id: session_id,
        day: day,
        cwd: cwd,
        git_branch: branch,
        model: model,
        requests: length(members),
        input: sum(members, :input),
        output: sum(members, :output),
        cache_read: sum(members, :cache_read),
        cache_write: sum(members, :cache_write),
        first_at: Enum.min(times, DateTime),
        last_at: Enum.max(times, DateTime)
      }
    end)
    |> Enum.sort_by(
      &{&1.day, &1.session_id || "", &1.cwd || "", &1.git_branch || "", &1.model || ""}
    )
  end

  @doc """
  Claude Code's own accounting in these transcripts: the last `cost-state`
  of each process (`sessionId` and `startTime`). It is cumulative per
  process, counts subagents and side calls that never appear as assistant
  lines, and prices them at list price: a cross-check, not a bill.
  """
  @spec cost_states([String.t()]) :: [cost_state()]
  def cost_states(paths) do
    paths
    |> Enum.flat_map(fn path ->
      case read_file(path) do
        {:ok, %{cost_states: states}} -> states
        {:error, _reason} -> []
      end
    end)
    |> Enum.group_by(&{&1.session_id, &1.start_time})
    |> Enum.map(fn {_key, states} -> Enum.max_by(states, &(&1.cost_usd || 0)) end)
    |> Enum.sort_by(&{&1.session_id, &1.start_time || 0})
  end

  @doc """
  The PRs each session linked (`pr-link` lines: `prRepository` and
  `prNumber`), in the order they were written, without repeats: the
  `pr_links` of `AgentBoard.Attribution.for_session/2`.
  """
  @spec pr_links([String.t()]) :: %{
          String.t() => [%{repository: String.t(), number: pos_integer()}]
        }
  def pr_links(paths) do
    paths
    |> Enum.flat_map(fn path ->
      case read_file(path) do
        {:ok, %{pr_links: links}} -> links
        {:error, _reason} -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.group_by(& &1.session_id, &Map.take(&1, [:repository, :number]))
  end

  defp take_line(line, acc) do
    if :binary.match(line, @wanted) == :nomatch do
      acc
    else
      case Fields.decode(line, @strings) do
        {:ok, %{"type" => "assistant"} = event} -> take_assistant(event, acc)
        {:ok, %{"type" => "cost-state"} = event} -> take_cost_state(event, acc)
        {:ok, %{"type" => "pr-link"} = event} -> take_pr_link(event, acc)
        {:ok, _other} -> acc
        :error -> %{acc | skipped: acc.skipped + 1}
      end
    end
  end

  defp take_assistant(%{"message" => %{"model" => "<synthetic>"}}, acc), do: acc

  defp take_assistant(event, acc) do
    case message(event) do
      nil ->
        %{acc | skipped: acc.skipped + 1}

      message ->
        {messages, order} = add_message(message, {acc.messages, acc.order})
        %{acc | messages: messages, order: order}
    end
  end

  defp message(%{"message" => %{"id" => id} = body} = event) when is_binary(id) do
    case time(event["timestamp"]) do
      {:ok, at} ->
        usage = body["usage"] || %{}

        %{
          id: id,
          session_id: event["sessionId"],
          at: at,
          cwd: event["cwd"],
          git_branch: event["gitBranch"],
          model: body["model"],
          input: count(usage["input_tokens"]),
          output: count(usage["output_tokens"]),
          cache_read: count(usage["cache_read_input_tokens"]),
          cache_write: count(usage["cache_creation_input_tokens"])
        }

      :error ->
        nil
    end
  end

  defp message(_event), do: nil

  defp add_message(%{id: id} = message, {by_id, order}) do
    case by_id do
      %{^id => first} -> {Map.put(by_id, id, merge(first, message)), order}
      _ -> {Map.put(by_id, id, message), [id | order]}
    end
  end

  defp take_cost_state(%{"sessionId" => session_id} = event, acc) when is_binary(session_id) do
    models =
      for {model, usage} <- event["modelUsage"] || %{}, is_map(usage), into: %{} do
        {model,
         %{
           input: count(usage["inputTokens"]),
           output: count(usage["outputTokens"]),
           cache_read: count(usage["cacheReadInputTokens"]),
           cache_write: count(usage["cacheCreationInputTokens"]),
           cost_usd: number(usage["costUSD"])
         }}
      end

    state = %{
      session_id: session_id,
      start_time: if(is_integer(event["startTime"]), do: event["startTime"]),
      cost_usd: number(event["totalCostUSD"]),
      models: models
    }

    %{acc | cost_states: [state | acc.cost_states]}
  end

  defp take_cost_state(_event, acc), do: %{acc | skipped: acc.skipped + 1}

  defp take_pr_link(
         %{"sessionId" => session_id, "prRepository" => repo, "prNumber" => number},
         acc
       )
       when is_binary(session_id) and is_binary(repo) and is_integer(number) and number > 0 do
    link = %{session_id: session_id, repository: repo, number: number}
    %{acc | pr_links: [link | acc.pr_links]}
  end

  defp take_pr_link(_event, acc), do: %{acc | skipped: acc.skipped + 1}

  defp time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _ -> :error
    end
  end

  defp time(_value), do: :error

  defp sum(members, key), do: members |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  defp count(n) when is_integer(n) and n > 0, do: n
  defp count(_), do: 0

  defp number(n) when is_number(n), do: n
  defp number(_), do: nil
end
