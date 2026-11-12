defmodule AgentBoard.Logs do
  @moduledoc """
  Warning and error lines from the board's own log and from the DeepSeek
  superagents' keepalive logs.

  This context reads files; it starts no process, writes nothing and never
  creates a timer. `read/3` stats each configured source, reads at most a
  bounded number of bytes after the last complete line and parses only
  complete lines. The caller keeps the returned per-file inode/offset state
  and a bounded buffer of entries, so one tick never repeats bytes and a
  closed panel costs nothing.

  The board's source is the file named by `AGENT_BOARD_LOG` (the launchd
  service sets it) or `~/Library/Logs/AgentBoard.log`. The superagent sources
  are built from the profiles in `Superagents.list/0`, never from a value a
  browser sends: `superagent` reads `dsh-superagent-keepalive.log` and
  `superagent-colmex` reads `dsh-superagent-colmex-keepalive.log` in
  `~/Library/Logs` (or `:superagent_log_dir`).

  A source that has no file or cannot be read is reported as `:missing` or
  `:unreadable`; the panel shows that state instead of inventing lines.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  @board_default "~/Library/Logs/AgentBoard.log"
  @logs_dir_default "~/Library/Logs"
  @initial_bytes 256 * 1024
  @max_bytes_per_tick 64 * 1024
  @max_line_chars 2_000
  @max_continuation_lines 60
  @cap 500

  # The board's logger format: "$date $time [$level] $message", one line per
  # event; a stack trace follows without a timestamp.
  @board_line ~r/\A(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,6})?) \[([a-z]+)\] ?(.*)\z/
  # keepalive.sh writes "date '+%Y-%m-%dT%H:%M:%S%z'" before each action.
  @keepalive_line ~r/\A(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{4})) ?(.*)\z/
  @profile ~r/\A[a-z0-9][a-z0-9-]{0,63}\z/

  defmodule Entry do
    @moduledoc "One warning or error line with its continuation lines."

    @enforce_keys [:source, :source_label, :level, :at, :message, :lines]
    defstruct [:seq, :source, :source_label, :level, :at, :message, :lines]

    @type t :: %__MODULE__{
            seq: pos_integer() | nil,
            source: String.t(),
            source_label: String.t(),
            level: :warning | :error,
            at: String.t(),
            message: String.t(),
            lines: [String.t()]
          }
  end

  @type source :: %{
          required(:id) => String.t(),
          required(:kind) => :board | :superagent,
          required(:label) => String.t(),
          required(:path) => String.t(),
          optional(:profile) => String.t()
        }
  @type status :: :ok | :missing | :unreadable

  @doc "The default number of entries the panel keeps in memory."
  def cap, do: @cap

  @doc """
  The sources the board may read: its own log first, then one keepalive log
  per registered superagent profile. Invalid profiles are skipped; a path is
  never taken from the browser.
  """
  @spec sources([map()]) :: [source()]
  def sources(superagents \\ []) do
    [board_source() | Enum.flat_map(List.wrap(superagents), &superagent_source/1)]
  end

  @doc "The board's own log source."
  @spec board_source() :: source()
  def board_source do
    %{id: "board", kind: :board, label: "Super Agent Super Board", path: board_path()}
  end

  @doc "The board log path: config, then `AGENT_BOARD_LOG`, then the safe default."
  @spec board_path() :: String.t()
  def board_path do
    configured = Application.get_env(:agent_board, :log_path) || System.get_env("AGENT_BOARD_LOG")

    case configured do
      path when is_binary(path) and path != "" -> Path.expand(path)
      _ -> Path.expand(@board_default)
    end
  end

  @doc """
  The keepalive source for one registered superagent, or `[]` when its
  profile cannot name a file. The profile is validated, never expanded from
  user input.
  """
  @spec superagent_source(map() | String.t()) :: [source()]
  def superagent_source(%{profile: profile} = superagent) do
    case superagent_log_path(profile) do
      nil ->
        []

      path ->
        [
          %{
            id: "superagent:" <> profile,
            kind: :superagent,
            label: superagent_label(superagent),
            path: path,
            profile: profile
          }
        ]
    end
  end

  def superagent_source(profile) when is_binary(profile),
    do: superagent_source(%{profile: profile})

  def superagent_source(_other), do: []

  @doc """
  The keepalive log path for a profile: `superagent` ->
  `dsh-superagent-keepalive.log`, `superagent-colmex` ->
  `dsh-superagent-colmex-keepalive.log`. Returns nil for anything that is not
  a plain profile name.
  """
  @spec superagent_log_path(term()) :: String.t() | nil
  def superagent_log_path(profile) when is_binary(profile) do
    if Regex.match?(@profile, profile) do
      suffix = String.replace_prefix(profile, "superagent", "")
      Path.join(superagent_log_dir(), "dsh-superagent#{suffix}-keepalive.log")
    end
  end

  def superagent_log_path(_profile), do: nil

  @doc "The directory that holds the superagent keepalive logs."
  @spec superagent_log_dir() :: String.t()
  def superagent_log_dir do
    case Application.get_env(:agent_board, :superagent_log_dir) do
      dir when is_binary(dir) and dir != "" -> Path.expand(dir)
      _ -> Path.expand(@logs_dir_default)
    end
  end

  @doc "A fresh reader state: no file has been read and no entry has a seq."
  @spec empty_state() :: %{files: map(), seq: non_neg_integer()}
  def empty_state, do: %{files: %{}, seq: 0}

  @doc """
  Read every source once.

  The first call for a source reads the last `:initial_bytes` (256 KiB) of the
  file so the panel opens with recent history; later calls read at most
  `:max_bytes` (64 KiB) after the last complete line. A rotated or truncated
  file restarts from its recent tail. Returns only warning/error entries,
  already numbered, plus the next state and one status per source.
  """
  @spec read([source()], map(), keyword()) :: %{
          entries: [Entry.t()],
          state: map(),
          statuses: %{String.t() => status()}
        }
  def read(sources, state, opts \\ []) when is_list(sources) do
    state = normalize_state(state)
    max_bytes = positive(Keyword.get(opts, :max_bytes, @max_bytes_per_tick), @max_bytes_per_tick)
    initial_bytes = positive(Keyword.get(opts, :initial_bytes, @initial_bytes), @initial_bytes)

    {entries, files, seq, statuses} =
      Enum.reduce(sources, {[], state.files, state.seq, %{}}, fn source,
                                                                 {entries, files, seq, statuses} ->
        previous = Map.get(files, source.id)

        case read_source(source, previous, max_bytes, initial_bytes) do
          {:ok, parsed, file, status} ->
            {new_entries, seq} = number(parsed, seq)

            {entries ++ new_entries, Map.put(files, source.id, file), seq,
             Map.put(statuses, source.id, status)}

          {:error, status, file} ->
            {entries, put_file(files, source.id, file), seq, Map.put(statuses, source.id, status)}
        end
      end)

    :telemetry.execute(
      [:agent_board, :logs, :read],
      %{sources: length(sources), entries: length(entries)},
      %{}
    )

    %{entries: entries, state: %{files: files, seq: seq}, statuses: statuses}
  end

  @doc """
  Keep at most `cap` entries, dropping the oldest. The buffer is a list in
  arrival order.
  """
  @spec append([Entry.t()], [Entry.t()], non_neg_integer()) :: [Entry.t()]
  def append(buffer, entries, cap \\ @cap) when is_list(buffer) and is_list(entries) do
    (buffer ++ entries) |> Enum.take(-max(cap, 0))
  end

  @doc "How many warnings and errors the buffer holds."
  @spec counts([Entry.t()]) :: %{warning: non_neg_integer(), error: non_neg_integer()}
  def counts(entries) do
    Enum.reduce(entries, %{warning: 0, error: 0}, fn
      %Entry{level: level}, acc -> Map.update!(acc, level, &(&1 + 1))
      _other, acc -> acc
    end)
  end

  @doc "The label for a level, in the viewer's language."
  @spec level_label(:warning | :error) :: String.t()
  def level_label(:warning),
    do: pgettext("log level", "warning")

  def level_label(:error),
    do: pgettext("log level", "error")

  @doc "The label for a source status, in the viewer's language."
  @spec status_label(status()) :: String.t()
  def status_label(:ok),
    do: pgettext("log source", "reading")

  def status_label(:missing),
    do:
      pgettext(
        "log source",
        "the file does not exist yet"
      )

  def status_label(:unreadable),
    do: pgettext("log source", "could not be read")

  @doc """
  Parse complete lines from one source. Exposed so the parser and its
  grouping can be tested without touching a file.
  """
  @spec parse(source(), String.t()) :: [Entry.t()]
  def parse(%{kind: :board} = source, text), do: parse_board(source, text)
  def parse(%{kind: :superagent} = source, text), do: parse_keepalive(source, text)
  def parse(_source, _text), do: []

  # -- reading --------------------------------------------------------------

  defp read_source(source, previous, max_bytes, initial_bytes) do
    case File.stat(source.path, time: :posix) do
      {:ok, %File.Stat{type: :regular, size: size, inode: inode}} ->
        read_regular(source, previous, size, inode, max_bytes, initial_bytes)

      {:ok, _stat} ->
        {:error, :unreadable, previous}

      {:error, :enoent} ->
        {:error, :missing, previous}

      {:error, _reason} ->
        {:error, :unreadable, previous}
    end
  rescue
    # The panel is a read-only observer: a malformed line or an unusual file
    # must show as unreadable, never take the board down or log to the same
    # file it is reading.
    _exception -> {:error, :unreadable, previous}
  end

  defp read_regular(source, previous, size, inode, max_bytes, initial_bytes) do
    {offset, fresh?} = offset_for(previous, size, inode, initial_bytes)

    if size <= offset do
      {:ok, [], %{path: source.path, inode: inode, offset: max(offset, size)}, :ok}
    else
      limit = if fresh?, do: initial_bytes, else: max_bytes
      read_from(source, offset, size, limit, fresh? && offset > 0, inode)
    end
  end

  # A file seen for the first time, rotated (new inode) or truncated reads its
  # recent tail. An existing file continues after the last complete line.
  defp offset_for(nil, size, _inode, initial_bytes), do: {max(0, size - initial_bytes), true}

  defp offset_for(%{inode: inode, offset: offset}, size, inode, _initial_bytes)
       when size >= offset,
       do: {offset, false}

  defp offset_for(_previous, size, _inode, initial_bytes),
    do: {max(0, size - initial_bytes), true}

  defp read_from(source, offset, size, limit, drop_first?, inode) do
    bytes = min(size - offset, limit)

    case pread(source.path, offset, bytes) do
      {:ok, data} when is_binary(data) and data != "" ->
        {text, next_offset} = complete_text(data, offset, limit, drop_first?)
        parsed = parse(source, text)

        {:ok, parsed, %{path: source.path, inode: inode, offset: next_offset}, :ok}

      {:ok, _empty} ->
        {:ok, [], %{path: source.path, inode: inode, offset: offset}, :ok}

      :eof ->
        {:ok, [], %{path: source.path, inode: inode, offset: offset}, :ok}

      {:error, _reason} ->
        {:error, :unreadable, %{path: source.path, inode: inode, offset: offset}}
    end
  end

  defp pread(path, offset, bytes) do
    case :file.open(path, [:read, :binary, :raw]) do
      {:ok, file} ->
        try do
          :file.pread(file, offset, bytes)
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Only complete lines are consumed; a partial last line is read again on the
  # next tick. A line longer than the whole budget is skipped instead of
  # stalling the reader forever.
  defp complete_text(data, offset, limit, drop_first?) do
    case :binary.matches(data, "\n") do
      [] ->
        if byte_size(data) >= limit, do: {"", offset + byte_size(data)}, else: {"", offset}

      matches ->
        {position, 1} = List.last(matches)
        complete = binary_part(data, 0, position + 1)
        text = if drop_first?, do: drop_leading_partial(complete), else: complete
        {text, offset + position + 1}
    end
  end

  defp drop_leading_partial(text) do
    case :binary.match(text, "\n") do
      :nomatch -> ""
      {position, 1} -> binary_part(text, position + 1, byte_size(text) - position - 1)
    end
  end

  defp normalize_state(%{files: files, seq: seq})
       when is_map(files) and is_integer(seq) and seq >= 0,
       do: %{files: files, seq: seq}

  defp normalize_state(_state), do: empty_state()

  defp put_file(files, _id, nil), do: files
  defp put_file(files, id, file), do: Map.put(files, id, file)

  defp number(entries, seq) do
    Enum.map_reduce(entries, seq, fn entry, n ->
      {%{entry | seq: n + 1}, n + 1}
    end)
  end

  defp positive(value, _default) when is_integer(value) and value > 0, do: value
  defp positive(_value, default), do: default

  # -- parsing --------------------------------------------------------------

  defp parse_board(source, text) do
    text
    |> lines()
    |> Enum.reduce({[], false}, &board_line(&1, &2, source))
    |> finish()
  end

  defp lines(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.map(&to_text/1)
  end

  # A log is bytes, and the panel's entries go to the browser as JSON, which
  # only carries UTF-8: one bad byte took every socket with the sheet open
  # down, on each reconnect. A BEAM started without a locale (launchd) writes
  # Latin-1, so that is how a line that is not UTF-8 is read.
  defp to_text(line) do
    if String.valid?(line), do: line, else: :unicode.characters_to_binary(line, :latin1)
  end

  defp board_line(line, {entries, open?}, source) do
    case Regex.run(@board_line, line) do
      [_, at, level, message] when level in ["warning", "error"] ->
        {[entry(source, level, at, message, []) | entries], true}

      [_, _at, _level, _message] ->
        # Any other timestamped line (info, debug) ends the open stack trace.
        {entries, false}

      _other ->
        board_continuation(line, entries, open?)
    end
  end

  defp board_continuation(line, entries, open?) do
    if open? and line != "" do
      {append_line(entries, line), true}
    else
      {entries, open?}
    end
  end

  defp parse_keepalive(source, text) do
    text
    |> lines()
    |> Enum.reduce({[], false}, &keepalive_line(&1, &2, source))
    |> finish()
  end

  defp keepalive_line(line, {entries, open?}, source) do
    case Regex.run(@keepalive_line, line) do
      [_, at, message] ->
        case keepalive_level(message) do
          nil -> {entries, false}
          level -> {[entry(source, level, at, message, []) | entries], true}
        end

      _other ->
        keepalive_continuation(line, entries, open?)
    end
  end

  defp keepalive_continuation(line, entries, open?) do
    if open? and String.trim(line) != "" do
      {append_line(entries, line), true}
    else
      {entries, open?}
    end
  end

  # The keepalive log has no `[level]` marker. Only lines that say they are a
  # problem are kept; "status 0"/"start exited 0" remain informational.
  defp keepalive_level(message) do
    cond do
      message =~ ~r/\Astart exited [1-9]\d*\b/ -> :error
      message =~ ~r/\Ano manager at\b/ -> :error
      message =~ ~r/\Astatus [1-9]\d*:/ -> :warning
      message =~ ~r/\b(error|failed|could not|unreadable|no such file)\b/i -> :error
      true -> nil
    end
  end

  defp entry(source, level, at, message, lines) do
    %Entry{
      source: source.id,
      source_label: source.label,
      level: level_atom(level),
      at: clip(at),
      message: clip(message),
      lines: lines
    }
  end

  defp level_atom("warning"), do: :warning
  defp level_atom("error"), do: :error
  defp level_atom(level) when level in [:warning, :error], do: level

  defp append_line([entry | rest], line) when length(entry.lines) < @max_continuation_lines do
    [%{entry | lines: entry.lines ++ [clip(line)]} | rest]
  end

  defp append_line(entries, _line), do: entries

  defp finish({entries, _open?}), do: Enum.reverse(entries)

  defp clip(line) do
    line = String.trim_trailing(line, "\r")

    if String.length(line) > @max_line_chars do
      String.slice(line, 0, @max_line_chars) <> "…"
    else
      line
    end
  end

  defp superagent_label(%{repository: %{owner: owner, name: name}}),
    do: "Superagente #{owner}/#{name}"

  defp superagent_label(%{profile: profile}), do: "Superagente #{profile}"
end
