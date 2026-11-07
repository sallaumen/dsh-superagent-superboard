defmodule AgentBoard.Usage.Ledger do
  @moduledoc """
  The usage ledger: what Claude Code, Codex and the DeepSeek Harness spent,
  one row per execution and UTC day, read from their local files.

  An execution is a Claude Code session (`sessionId`), a Codex thread (its
  id) or a harness ticket (its folder under `~/.dsh/sessions`). A row also
  keeps the cwd, branch and model, and counts messages (`requests`), input
  (without the cache), output, cache read and cache write tokens. Each
  source is counted by its own reader:

    * Claude Code: `AgentBoard.Usage.ClaudeCode`. A message is one row in
      `usage_messages`, once per `message.id` across every file; a later
      copy merges its counts by the largest value and keeps the session
      of the first copy stored.
    * The harness: `AgentBoard.ExecutorUsage.read_transcript/1`, the parser
      the task inspector uses, one row per message.
    * Codex: `AgentBoard.Usage.Codex`, a thread's daily growth of its
      cumulative total, written straight to the ledger; its input excludes
      the cached input here, as for the other two.

  `refresh/0` reads only the files whose size or modification time changed
  since the last read (`usage_files`); a Claude Code transcript that only
  grew is read from where the last read stopped. A row is written only when
  its numbers change, so reading the same files again changes nothing. A
  file that cannot be read keeps its reason in `usage_files.error` and is
  tried again on the next run; the other files go on.

  The tokens are measured. There is no cost here: each source has its own
  currency (DeepSeek balance, the Claude Max subscription, the ChatGPT plan's
  weekly window), and the ledger never adds them up. `limits/0` is the last
  quota Codex reported.
  """

  import Ecto.Query

  alias AgentBoard.ExecutorUsage
  alias AgentBoard.Repo
  alias AgentBoard.Usage.{ClaudeCode, Codex}

  require Logger

  @sources ~w(claude_code codex dsh)
  @counts [:requests, :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens]
  @tokens [:input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens]
  @fingerprint_bytes 4_096
  @chunk 2_000

  @type source :: String.t()
  @type summary :: %{read: non_neg_integer(), failed: non_neg_integer(), rows: non_neg_integer()}

  @doc "The sources the ledger reads."
  @spec sources() :: [source()]
  def sources, do: @sources

  @doc """
  Reads every new or changed file of every source, oldest first, and
  updates the ledger. Returns how many files were read, how many failed
  and how many ledger rows changed.
  """
  @spec refresh() :: summary()
  def refresh do
    known = known_files()
    listed = listed_files()
    changed = Enum.filter(listed, &changed?(&1, known))
    threads = if Enum.any?(changed, &(&1.source == "codex")), do: codex_threads(), else: %{}

    changed
    |> units(listed)
    |> Enum.sort_by(fn unit ->
      {unit.files |> Enum.map(& &1.mtime) |> Enum.max(), hd(unit.files).path}
    end)
    |> Enum.reduce(%{read: 0, failed: 0, rows: 0}, fn unit, summary ->
      files = length(unit.files)

      case ingest(unit, known, threads) do
        {:ok, rows} -> %{summary | read: summary.read + files, rows: summary.rows + rows}
        {:error, _reason} -> %{summary | failed: summary.failed + files}
      end
    end)
  end

  # What is read together: one file, or every rollout of a Codex thread
  # one of whose files changed (a thread's total runs across its files).
  defp units(changed, listed) do
    {codex, others} = Enum.split_with(changed, &(&1.source == "codex"))

    segments =
      listed
      |> Enum.filter(&(&1.source == "codex"))
      |> Enum.group_by(&Codex.thread_id(&1.path))

    threads =
      codex
      |> Enum.group_by(&Codex.thread_id(&1.path))
      |> Enum.flat_map(fn
        {nil, files} ->
          Enum.map(files, &%{source: "codex", thread: nil, files: [&1]})

        {thread, _files} ->
          files = Enum.sort_by(Map.fetch!(segments, thread), &Path.basename(&1.path))
          [%{source: "codex", thread: thread, files: files}]
      end)

    Enum.map(others, &%{source: &1.source, files: [&1]}) ++ threads
  end

  @doc """
  The ledger's totals per source and UTC day since `since` (inclusive). Each
  source stays its own row: the ledger never adds two sources together.
  """
  @spec daily(Date.t()) :: [map()]
  def daily(%Date{} = since) do
    Repo.all(
      from l in "usage_ledger",
        where: l.day >= ^since,
        group_by: [l.source, l.day],
        order_by: [l.day, l.source],
        select: %{
          source: l.source,
          day: l.day,
          executions: count(l.execution_id, :distinct),
          requests: type(sum(l.requests), :integer),
          input_tokens: type(sum(l.input_tokens), :integer),
          output_tokens: type(sum(l.output_tokens), :integer),
          cache_read_tokens: type(sum(l.cache_read_tokens), :integer),
          cache_write_tokens: type(sum(l.cache_write_tokens), :integer)
        }
    )
  end

  @doc "The last quota reading of each plan limit, newest first."
  @spec limits() :: [map()]
  def limits do
    Repo.all(
      from l in "usage_limits",
        order_by: [desc: l.observed_at],
        select: %{
          source: l.source,
          limit_id: l.limit_id,
          plan_type: l.plan_type,
          primary_used_percent: l.primary_used_percent,
          primary_window_minutes: l.primary_window_minutes,
          primary_resets_at: type(l.primary_resets_at, :utc_datetime),
          secondary_used_percent: l.secondary_used_percent,
          secondary_window_minutes: l.secondary_window_minutes,
          secondary_resets_at: type(l.secondary_resets_at, :utc_datetime),
          has_credits: l.has_credits,
          unlimited: l.unlimited,
          credits_balance: l.credits_balance,
          reached: l.reached,
          execution_id: l.execution_id,
          observed_at: type(l.observed_at, :utc_datetime_usec)
        }
    )
  end

  ## Files

  defp listed_files do
    Enum.flat_map(@sources, fn source -> source |> paths() |> Enum.flat_map(&stat(source, &1)) end)
  end

  defp stat(source, path) do
    case File.stat(path, time: :posix) do
      {:ok, %{type: :regular, size: size, mtime: mtime}} ->
        [%{source: source, path: path, size: size, mtime: mtime}]

      _ ->
        []
    end
  end

  defp paths("claude_code"), do: ClaudeCode.transcripts()
  defp paths("codex"), do: Codex.rollouts() ++ Codex.rollouts(Codex.archived_dir())

  defp paths("dsh") do
    ExecutorUsage.sessions_dir()
    |> Path.join("*/*/session.v4.jsonl.zstd")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp known_files do
    Repo.all(
      from f in "usage_files",
        select:
          {f.path,
           %{
             size: f.size,
             mtime: f.mtime,
             offset: f.offset,
             fingerprint: f.fingerprint,
             error: f.error
           }}
    )
    |> Map.new()
  end

  defp changed?(file, known) do
    case Map.get(known, file.path) do
      %{size: size, mtime: mtime, error: nil} -> size != file.size or mtime != file.mtime
      _ -> true
    end
  end

  ## Ingest

  defp ingest(unit, known, threads) do
    result =
      try do
        transact(unit, known, threads)
      rescue
        error -> {:error, Exception.message(error)}
      end

    case result do
      {:ok, rows} ->
        {:ok, rows}

      {:error, reason} ->
        paths = Enum.map_join(unit.files, ", ", & &1.path)
        Logger.warning("usage ledger: #{unit.source} #{paths} unreadable: #{inspect(reason)}")

        Enum.each(
          unit.files,
          &put_file(&1, %{offset: 0, fingerprint: nil, skipped: 0}, inspect(reason))
        )

        {:error, reason}
    end
  end

  defp transact(unit, known, threads) do
    Repo.transaction(
      fn ->
        case read(unit, known, threads) do
          {:ok, rows, states} ->
            Enum.each(states, &put_read/1)
            rows

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end,
      timeout: :infinity
    )
  end

  defp read(%{source: "claude_code", files: [file]}, known, _threads) do
    from = resume_offset(file, Map.get(known, file.path))

    with {:ok, read} <- ClaudeCode.read_file(file.path, from: from) do
      rows =
        Enum.map(read.messages, fn message ->
          message_row(message, message.session_id || session_from_path(file.path))
        end)

      changed = "claude_code" |> store_messages(rows) |> rebuild("claude_code")

      state = %{
        offset: read.offset,
        fingerprint: fingerprint(file.path, read.offset),
        skipped: read.skipped
      }

      {:ok, changed, [{file, state}]}
    end
  end

  defp read(%{source: "dsh", files: [file]}, _known, _threads) do
    session_dir = Path.dirname(file.path)
    execution = session_dir |> Path.dirname() |> Path.basename()
    prefix = "#{execution}/#{Path.basename(session_dir)}:"

    with {:ok, transcript} <- ExecutorUsage.read_file(file.path) do
      {rows, skipped} =
        Enum.reduce(transcript.messages, {[], 0}, fn
          %{at: nil}, {rows, skipped} ->
            {rows, skipped + 1}

          message, {rows, skipped} ->
            row =
              message
              |> Map.merge(%{
                id: prefix <> to_string(message.key),
                cwd: transcript.cwd,
                git_branch: nil
              })
              |> message_row(execution)

            {[row | rows], skipped}
        end)

      changed = "dsh" |> store_messages(Enum.reverse(rows)) |> rebuild("dsh")
      {:ok, changed, [{file, %{offset: 0, fingerprint: nil, skipped: skipped}}]}
    end
  end

  defp read(%{source: "codex", thread: nil}, _known, _threads), do: {:error, :no_thread_id}

  defp read(%{source: "codex", thread: thread_id, files: files}, _known, threads) do
    with {:ok, rollout} <- Codex.read_thread(Enum.map(files, & &1.path)) do
      thread = Map.get(threads, thread_id, %{})

      rows =
        Enum.map(rollout.days, fn day ->
          %{
            day: day.day,
            cwd: thread[:cwd],
            git_branch: thread[:git_branch],
            model: thread[:model],
            requests: day.requests,
            input_tokens: max(day.input - day.cached_input, 0),
            output_tokens: day.output,
            cache_read_tokens: day.cached_input,
            cache_write_tokens: day.cache_write,
            first_at: day.first_at,
            last_at: day.last_at
          }
        end)

      changed = replace_execution("codex", thread_id, rows)
      put_limits("codex", thread_id, rollout.rate_limits)

      # The thread's unreadable lines are counted once, on its last file.
      {earlier, [last]} = Enum.split(files, -1)
      states = Enum.map(earlier, &{&1, %{offset: 0, fingerprint: nil, skipped: 0}})
      {:ok, changed, states ++ [{last, %{offset: 0, fingerprint: nil, skipped: rollout.skipped}}]}
    end
  end

  defp codex_threads do
    case Codex.threads() do
      {:ok, threads} ->
        Map.new(threads, &{&1.id, &1})

      {:error, reason} ->
        Logger.warning("usage ledger: Codex threads unreadable: #{inspect(reason)}")
        %{}
    end
  end

  defp session_from_path(path) do
    case Path.split(Path.relative_to(path, ClaudeCode.projects_dir())) do
      [_project, file] -> Path.basename(file, ".jsonl")
      [_project, session | _rest] -> session
      _ -> Path.basename(path, ".jsonl")
    end
  end

  # A transcript that only grew is read from where the last read stopped,
  # when the bytes just before that point are the ones read then.
  defp resume_offset(_file, nil), do: 0

  defp resume_offset(file, %{offset: offset, fingerprint: print}) when offset > 0 do
    if file.size >= offset and print != nil and fingerprint(file.path, offset) == print,
      do: offset,
      else: 0
  end

  defp resume_offset(_file, _previous), do: 0

  defp fingerprint(_path, 0), do: nil

  defp fingerprint(path, offset) do
    start = max(offset - @fingerprint_bytes, 0)

    case :file.open(path, [:read, :raw, :binary]) do
      {:ok, fd} ->
        try do
          case :file.pread(fd, start, offset - start) do
            {:ok, bytes} -> :erlang.phash2(bytes, 4_294_967_296)
            _ -> nil
          end
        after
          :file.close(fd)
        end

      {:error, _reason} ->
        nil
    end
  end

  defp put_read({file, state}), do: put_file(file, state, nil)

  defp put_file(file, state, error) do
    now = DateTime.utc_now()

    Repo.insert_all(
      "usage_files",
      [
        %{
          source: file.source,
          path: file.path,
          size: file.size,
          mtime: file.mtime,
          offset: state.offset,
          fingerprint: state.fingerprint,
          skipped: state.skipped,
          error: error,
          read_at: now,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict:
        {:replace,
         [:source, :size, :mtime, :offset, :fingerprint, :skipped, :error, :read_at, :updated_at]},
      conflict_target: :path
    )
  end

  ## Messages (Claude Code and the harness)

  defp message_row(message, execution) do
    %{
      message_id: message.id,
      execution_id: execution,
      at: message.at,
      day: DateTime.to_date(message.at),
      cwd: message.cwd,
      git_branch: message.git_branch,
      model: message.model,
      input_tokens: message.input,
      output_tokens: message.output,
      cache_read_tokens: message.cache_read,
      cache_write_tokens: message.cache_write
    }
  end

  # Inserts the new messages and raises the counts of known ones; returns
  # the executions whose messages changed.
  defp store_messages(source, rows) do
    rows
    |> Enum.chunk_every(@chunk)
    |> Enum.reduce(MapSet.new(), &store_chunk(source, &1, &2))
  end

  defp store_chunk(source, chunk, affected) do
    stored = stored_messages(source, Enum.map(chunk, & &1.message_id))

    {new, affected} =
      Enum.reduce(chunk, {[], affected}, fn row, {new, affected} ->
        case Map.get(stored, row.message_id) do
          nil -> {[Map.put(row, :source, source) | new], MapSet.put(affected, row.execution_id)}
          old -> {new, raise_counts(old, row, affected)}
        end
      end)

    Repo.insert_all("usage_messages", Enum.reverse(new), on_conflict: :nothing)
    affected
  end

  defp stored_messages(source, ids) do
    Repo.all(
      from m in "usage_messages",
        where: m.source == ^source and m.message_id in type(^ids, {:array, :string}),
        select:
          {m.message_id,
           %{
             id: m.id,
             execution_id: m.execution_id,
             input_tokens: m.input_tokens,
             output_tokens: m.output_tokens,
             cache_read_tokens: m.cache_read_tokens,
             cache_write_tokens: m.cache_write_tokens
           }}
    )
    |> Map.new()
  end

  defp raise_counts(old, row, affected) do
    merged = Map.new(@tokens, &{&1, max(Map.fetch!(old, &1), Map.fetch!(row, &1))})

    if merged == Map.take(old, @tokens) do
      affected
    else
      Repo.update_all(from(m in "usage_messages", where: m.id == ^old.id),
        set: Enum.to_list(merged)
      )

      MapSet.put(affected, old.execution_id)
    end
  end

  # The ledger rows of these executions, recomputed from their messages.
  defp rebuild(executions, source) do
    executions = MapSet.to_list(executions)

    grouped =
      Repo.all(
        from m in "usage_messages",
          where: m.source == ^source and m.execution_id in type(^executions, {:array, :string}),
          group_by: [m.execution_id, m.day, m.cwd, m.git_branch, m.model],
          select: %{
            execution_id: m.execution_id,
            day: m.day,
            cwd: m.cwd,
            git_branch: m.git_branch,
            model: m.model,
            requests: type(count(m.id), :integer),
            input_tokens: type(sum(m.input_tokens), :integer),
            output_tokens: type(sum(m.output_tokens), :integer),
            cache_read_tokens: type(sum(m.cache_read_tokens), :integer),
            cache_write_tokens: type(sum(m.cache_write_tokens), :integer),
            first_at: type(min(m.at), :utc_datetime_usec),
            last_at: type(max(m.at), :utc_datetime_usec)
          }
      )
      |> Enum.group_by(& &1.execution_id, &Map.delete(&1, :execution_id))

    executions
    |> Enum.map(&replace_execution(source, &1, Map.get(grouped, &1, [])))
    |> Enum.sum()
  end

  ## Ledger rows

  # Writes only what differs from the stored rows of this execution.
  defp replace_execution(source, execution, rows) do
    stored =
      Repo.all(
        from l in "usage_ledger",
          where: l.source == ^source and l.execution_id == ^execution,
          select: %{
            id: l.id,
            day: l.day,
            cwd: l.cwd,
            git_branch: l.git_branch,
            model: l.model,
            requests: l.requests,
            input_tokens: l.input_tokens,
            output_tokens: l.output_tokens,
            cache_read_tokens: l.cache_read_tokens,
            cache_write_tokens: l.cache_write_tokens,
            first_at: type(l.first_at, :utc_datetime_usec),
            last_at: type(l.last_at, :utc_datetime_usec)
          }
      )
      |> Map.new(&{key(&1), &1})

    now = DateTime.utc_now()
    wanted = Map.new(rows, &{key(&1), &1})

    inserts =
      for {k, row} <- wanted, not Map.has_key?(stored, k) do
        Map.merge(row, %{
          source: source,
          execution_id: execution,
          inserted_at: now,
          updated_at: now
        })
      end

    updates =
      for {k, row} <- wanted, old = stored[k], old != nil, values(old) != values(row) do
        Repo.update_all(from(l in "usage_ledger", where: l.id == ^old.id),
          set: Enum.to_list(Map.put(values(row), :updated_at, now))
        )
      end

    deletes = for {k, old} <- stored, not Map.has_key?(wanted, k), do: old.id

    if inserts != [], do: Repo.insert_all("usage_ledger", inserts)

    if deletes != [],
      do:
        Repo.delete_all(
          from(l in "usage_ledger", where: l.id in type(^deletes, {:array, :integer}))
        )

    length(inserts) + length(updates) + length(deletes)
  end

  defp key(row), do: {row.day, row.cwd, row.git_branch, row.model}

  # Times compare at microsecond precision: a transcript writes
  # milliseconds, the database gives microseconds back.
  defp values(row) do
    row
    |> Map.take(@counts ++ [:first_at, :last_at])
    |> Map.update!(:first_at, &usec/1)
    |> Map.update!(:last_at, &usec/1)
  end

  defp usec(%DateTime{microsecond: {us, _precision}} = at), do: %{at | microsecond: {us, 6}}

  ## Limits

  defp put_limits(_source, _execution, nil), do: :ok

  defp put_limits(source, execution, limits) do
    now = DateTime.utc_now()

    row = %{
      source: source,
      limit_id: limits.limit_id,
      plan_type: limits.plan_type,
      primary_used_percent: get_in(limits, [:primary, :used_percent]),
      primary_window_minutes: get_in(limits, [:primary, :window_minutes]),
      primary_resets_at: get_in(limits, [:primary, :resets_at]),
      secondary_used_percent: get_in(limits, [:secondary, :used_percent]),
      secondary_window_minutes: get_in(limits, [:secondary, :window_minutes]),
      secondary_resets_at: get_in(limits, [:secondary, :resets_at]),
      has_credits: get_in(limits, [:credits, :has_credits]),
      unlimited: get_in(limits, [:credits, :unlimited]),
      credits_balance: get_in(limits, [:credits, :balance]),
      reached: limits.reached,
      execution_id: execution,
      observed_at: limits.observed_at,
      inserted_at: now,
      updated_at: now
    }

    # A reading replaces the stored one only when it is newer.
    stored =
      Repo.one(
        from l in "usage_limits",
          where: l.source == ^source,
          where: ^limit_filter(limits.limit_id),
          select: %{id: l.id, observed_at: type(l.observed_at, :utc_datetime_usec)}
      )

    cond do
      stored == nil ->
        Repo.insert_all("usage_limits", [row])

      DateTime.compare(limits.observed_at, stored.observed_at) == :gt ->
        Repo.update_all(from(l in "usage_limits", where: l.id == ^stored.id),
          set: row |> Map.drop([:inserted_at]) |> Enum.to_list()
        )

      true ->
        :ok
    end

    :ok
  end

  defp limit_filter(nil), do: dynamic([l], is_nil(l.limit_id))
  defp limit_filter(id), do: dynamic([l], l.limit_id == ^id)
end
