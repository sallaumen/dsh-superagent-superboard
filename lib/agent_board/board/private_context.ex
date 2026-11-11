defmodule AgentBoard.Board.PrivateContext do
  @moduledoc """
  What a task needs that must never reach GitHub: a note with passwords or
  keys, images, a whole folder of mocks. It lives on this machine, outside any
  repository, so no `git add` in an agent's worktree can sweep it up:

      <root>/<owner>/<repo>/<dir>/notes.md
      <root>/<owner>/<repo>/<dir>/files/...

  The issue carries only the folder's path (`IssueBody.with_private/3`), never
  its content, and the agent reads the folder on the same machine.

  Every name on disk is chosen here: the folder is `req-<hash>` (a request
  from the composer, the same words give the same folder, so a retry reuses
  it) or `issue-<n>` (made later from the inspector); a file name goes through
  `Attachments.safe_name/1`. Folders are 0700 and files 0600. A local folder
  the owner names is copied, never linked, and only from under `$HOME`,
  outside hidden folders, without following links, within `@max_files` and
  `@max_bytes`.
  """

  alias AgentBoard.Board.Attachments

  @dir ~r/\A(?:req-[0-9a-f]{16}|issue-[1-9][0-9]{0,9})\z/
  @marker ~r/<!-- agent-board:private (req-[0-9a-f]{16}|issue-[1-9][0-9]{0,9}) -->/
  @segment ~r/\A[A-Za-z0-9_.-]{1,100}\z/
  @note "notes.md"
  @max_note_bytes 256_000
  @max_files 2_000
  @max_bytes 200_000_000
  @skipped ~w(.git node_modules _build deps .elixir_ls)
  @roles %{"reference" => "", "before" => "before--", "after" => "after--"}

  @type dir :: String.t()

  @doc "Where every private folder lives; outside any repository."
  @spec root() :: String.t()
  def root do
    Application.get_env(:agent_board, :private_root) ||
      Path.expand("~/.local/share/agent-board/private")
  end

  @doc "The folder of a request from the composer: the same words, the same folder."
  @spec request_dir(map(), String.t()) :: dir()
  def request_dir(%{id: id}, text) do
    hash = :crypto.hash(:sha256, "#{id}\0#{String.trim(text)}") |> Base.encode16(case: :lower)
    "req-" <> binary_part(hash, 0, 16)
  end

  @doc "The folder made for an issue that has none."
  @spec issue_dir(pos_integer()) :: dir()
  def issue_dir(number) when is_integer(number) and number > 0, do: "issue-#{number}"

  @doc "Whether a folder name is one this module could have chosen."
  @spec valid_dir?(term()) :: boolean()
  def valid_dir?(dir), do: is_binary(dir) and String.match?(dir, @dir)

  @doc "The marker an issue body carries for its folder; invisible on GitHub."
  @spec marker(dir()) :: String.t()
  def marker(dir), do: "<!-- agent-board:private #{dir} -->"

  @doc "A task's folder: the one its body names, or the one made for its issue."
  @spec for_task(map(), map()) :: dir() | nil
  def for_task(repository, %{body: body, number: number}) do
    case body && Regex.run(@marker, body, capture: :all_but_first) do
      [dir] ->
        dir

      _none ->
        if is_integer(number) and exists?(repository, issue_dir(number)), do: issue_dir(number)
    end
  end

  @doc "The folder's absolute path."
  @spec path(map(), dir()) :: String.t()
  def path(%{owner: owner, name: name}, dir) do
    true = valid_dir?(dir) and String.match?(owner, @segment) and String.match?(name, @segment)
    Path.join([root(), owner, name, dir])
  end

  @doc "Whether the folder exists."
  @spec exists?(map(), dir()) :: boolean()
  def exists?(repository, dir), do: valid_dir?(dir) and File.dir?(path(repository, dir))

  @doc "The private note; empty when there is none."
  @spec read_note(map(), dir()) :: String.t()
  def read_note(repository, dir) do
    case File.read(Path.join(path(repository, dir), @note)) do
      {:ok, text} -> text
      {:error, _none} -> ""
    end
  end

  @doc "Writes the note, replacing the file at once (a crash leaves the old one)."
  @spec write_note(map(), dir(), String.t()) :: :ok | {:error, :too_large | File.posix()}
  def write_note(_repository, _dir, text) when byte_size(text) > @max_note_bytes,
    do: {:error, :too_large}

  def write_note(repository, dir, text) when is_binary(text) do
    with :ok <- ensure(repository, dir) do
      write_private(Path.join(path(repository, dir), @note), text)
    end
  end

  @doc """
  Stores a picked file under `files/`. The role names it: `before--` and
  `after--` pair a before and an after the agent can compare.
  """
  @spec put_file(map(), dir(), String.t(), binary(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def put_file(repository, dir, name, content, role \\ "reference") do
    safe = Map.get(@roles, role, "") <> Attachments.safe_name(name)
    relative = Path.join("files", safe)

    with :ok <- ensure(repository, dir, "files"),
         :ok <- write_private(Path.join(path(repository, dir), relative), content) do
      {:ok, relative}
    end
  end

  @doc """
  Copies a local folder the owner named into `files/<folder>/`. Answers how
  many files and bytes were copied, or why nothing was.
  """
  @spec import_folder(map(), dir(), String.t()) ::
          {:ok, %{name: String.t(), files: non_neg_integer(), bytes: non_neg_integer()}}
          | {:error, :not_a_folder | :outside_home | :hidden | :inside_private | :too_large}
  def import_folder(repository, dir, source) do
    with {:ok, source} <- allowed_source(source),
         {:ok, entries} <- walk(source),
         name = Attachments.safe_name(Path.basename(source)),
         target = Path.join([path(repository, dir), "files", name]),
         :ok <- ensure(repository, dir, Path.join("files", name)) do
      # A file that cannot be read is left out instead of stopping the copy.
      copied =
        Enum.filter(entries, fn {relative, _bytes} -> copy(source, target, relative) == :ok end)

      {:ok, %{name: name, files: length(copied), bytes: Enum.sum(Enum.map(copied, &elem(&1, 1)))}}
    end
  end

  @doc "Whether a local folder can be copied, and how much it holds; copies nothing."
  @spec check_folder(String.t()) ::
          {:ok,
           %{
             path: String.t(),
             name: String.t(),
             files: non_neg_integer(),
             bytes: non_neg_integer()
           }}
          | {:error,
             :not_a_folder | :outside_home | :hidden | :inside_private | :too_large | :empty}
  def check_folder(source) do
    with {:ok, source} <- allowed_source(source),
         {:ok, [_ | _] = entries} <- walk(source) |> nonempty() do
      {:ok,
       %{
         path: source,
         name: Attachments.safe_name(Path.basename(source)),
         files: length(entries),
         bytes: entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()
       }}
    end
  end

  defp nonempty({:ok, []}), do: {:error, :empty}
  defp nonempty(other), do: other

  @doc """
  Writes what the composer gathered for a request before any issue names the
  folder: the note, the picked files with their roles and the named folders.
  The first failure stops it and is named by one atom.
  """
  @spec store(map(), dir(), map()) :: :ok | {:error, atom()}
  def store(repository, dir, private) do
    note = Map.get(private, :note, "")

    with :ok <- ensure(repository, dir),
         :ok <- if(String.trim(note) == "", do: :ok, else: write_note(repository, dir, note)),
         :ok <- each(Map.get(private, :files, []), &stored_file(repository, dir, &1)),
         :ok <- each(Map.get(private, :folders, []), &imported(repository, dir, &1)) do
      :ok
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _other} -> {:error, :unwritable}
    end
  end

  defp each(items, fun),
    do: Enum.reduce_while(items, :ok, fn item, :ok -> fun.(item) |> continue() end)

  defp continue(:ok), do: {:cont, :ok}
  defp continue({:ok, _stored}), do: {:cont, :ok}
  defp continue(error), do: {:halt, error}

  defp stored_file(repository, dir, %{name: name, content: content} = file),
    do: put_file(repository, dir, name, content, Map.get(file, :role, "reference"))

  defp imported(repository, dir, source), do: import_folder(repository, dir, source)

  @doc "Every file in the folder, relative to it, the note first; at most 500. No link is followed."
  @spec list(map(), dir()) :: [%{path: String.t(), bytes: non_neg_integer(), image?: boolean()}]
  def list(repository, dir) do
    repository
    |> path(dir)
    |> regular_files("", 500)
    |> Enum.map(fn {relative, size} ->
      %{path: relative, bytes: size, image?: Attachments.image?(relative)}
    end)
    |> Enum.sort_by(&{&1.path != @note, &1.path})
  end

  defp regular_files(base, relative, room) do
    case File.ls(Path.join(base, relative)) do
      {:ok, names} ->
        names |> Enum.sort() |> Enum.reduce_while([], &take(base, relative, room, &1, &2))

      {:error, _missing} ->
        []
    end
  end

  defp take(_base, _relative, room, _name, found) when length(found) >= room, do: {:halt, found}

  defp take(base, relative, room, name, found),
    do: {:cont, found ++ entry(base, Path.join(relative, name), room - length(found))}

  defp entry(base, relative, room) do
    case File.lstat(Path.join(base, relative)) do
      {:ok, %File.Stat{type: :directory}} -> regular_files(base, relative, room)
      {:ok, %File.Stat{type: :regular, size: size}} -> [{relative, size}]
      _link -> []
    end
  end

  @doc "Removes one file under `files/`; the note is cleared with `write_note/3`."
  @spec remove_file(map(), dir(), String.t()) :: :ok | :error
  def remove_file(repository, dir, relative) do
    case resolve(repository, dir, relative) do
      {:ok, "files/" <> _ = _relative, absolute} ->
        if File.rm(absolute) == :ok, do: :ok, else: :error

      _other ->
        :error
    end
  end

  @doc "A raster image in the folder and its kind, for the board's own page."
  @spec image(map(), dir(), String.t()) :: {:ok, binary(), atom()} | :error
  def image(repository, dir, relative) do
    with {:ok, _relative, absolute} <- resolve(repository, dir, relative),
         kind when not is_nil(kind) <- Attachments.image_kind(absolute),
         {:ok, content} <- File.read(absolute) do
      {:ok, content, kind}
    else
      _not_an_image -> :error
    end
  end

  # A relative path from a request: plain segments only, a regular file, no link.
  defp resolve(repository, dir, relative) when is_binary(relative) do
    segments = Path.split(relative)

    with true <- valid_dir?(dir),
         true <- segments != [] and Enum.all?(segments, &safe_segment?/1),
         absolute = Path.join(path(repository, dir), relative),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(absolute),
         false <- link_on_the_way?(path(repository, dir), segments) do
      {:ok, relative, absolute}
    else
      _refused -> :error
    end
  end

  defp resolve(_repository, _dir, _relative), do: :error

  defp safe_segment?(segment),
    do: String.match?(segment, @segment) and segment not in [".", ".."]

  defp link_on_the_way?(base, segments) do
    segments
    |> Enum.drop(-1)
    |> Enum.scan(base, &Path.join(&2, &1))
    |> Enum.any?(&match?({:ok, %File.Stat{type: :symlink}}, File.lstat(&1)))
  end

  # An empty or relative path would resolve against the board's own working
  # directory (its checkout), never the owner's shell: refused.
  defp allowed_source(source) when is_binary(source) do
    home = Path.expand("~")
    trimmed = String.trim(source)
    expanded = Path.expand(trimmed)
    below_home = Path.split(Path.relative_to(expanded, home))

    cond do
      not absolute_or_home?(trimmed) ->
        {:error, :not_a_folder}

      not String.starts_with?(expanded, home <> "/") ->
        {:error, :outside_home}

      Enum.any?(below_home, &String.starts_with?(&1, ".")) ->
        {:error, :hidden}

      # A link on the way could lead out of home or into a hidden folder.
      link_on_the_way?(home, below_home ++ ["leaf"]) ->
        {:error, :outside_home}

      String.starts_with?(expanded <> "/", root() <> "/") ->
        {:error, :inside_private}

      match?({:ok, %File.Stat{type: :directory}}, File.lstat(expanded)) ->
        {:ok, expanded}

      true ->
        {:error, :not_a_folder}
    end
  end

  defp allowed_source(_source), do: {:error, :not_a_folder}

  defp absolute_or_home?(""), do: false
  defp absolute_or_home?("~" <> _rest), do: true
  defp absolute_or_home?(path), do: Path.type(path) == :absolute

  # Regular files only, no link followed, the tool folders skipped; stops as
  # soon as a limit is passed so a home folder named by mistake costs nothing.
  defp walk(source) do
    case walk(source, "", {[], 0, 0}) do
      {:ok, {entries, _count, _bytes}} -> {:ok, Enum.reverse(entries)}
      :too_large -> {:error, :too_large}
    end
  end

  defp walk(source, relative, acc) do
    case File.ls(Path.join(source, relative)) do
      {:ok, names} ->
        names
        |> Enum.reject(&(&1 in @skipped or String.starts_with?(&1, ".")))
        |> Enum.sort()
        |> Enum.reduce_while({:ok, acc}, &step(source, relative, &1, &2))

      {:error, _unreadable} ->
        {:ok, acc}
    end
  end

  defp step(source, relative, name, {:ok, acc}) do
    case visit(source, Path.join(relative, name), acc) do
      {:ok, acc} -> {:cont, {:ok, acc}}
      :too_large -> {:halt, :too_large}
    end
  end

  defp visit(source, relative, {entries, count, bytes} = acc) do
    case File.lstat(Path.join(source, relative)) do
      {:ok, %File.Stat{type: :directory}} ->
        walk(source, relative, acc)

      {:ok, %File.Stat{type: :regular, size: size}} ->
        if count + 1 > @max_files or bytes + size > @max_bytes,
          do: :too_large,
          else: {:ok, {[{relative, size} | entries], count + 1, bytes + size}}

      _link_or_device ->
        {:ok, acc}
    end
  end

  defp copy(source, target, relative) do
    safe = relative |> Path.split() |> Enum.map(&Attachments.safe_name/1) |> Path.join()
    destination = Path.join(target, safe)

    with :ok <- mkdir_private(Path.dirname(destination)),
         :ok <- File.cp(Path.join(source, relative), destination) do
      File.chmod(destination, 0o600)
    end
  end

  defp ensure(repository, dir, below \\ nil) do
    full = if below, do: Path.join(path(repository, dir), below), else: path(repository, dir)
    mkdir_private(full)
  end

  # Each level made here is 0700, the root included: another user on the
  # machine reads nothing.
  defp mkdir_private(full) do
    full
    |> Path.split()
    |> Enum.scan(&Path.join(&2, &1))
    |> Enum.reject(&File.dir?/1)
    |> Enum.reduce_while(:ok, fn level, :ok ->
      case File.mkdir(level) do
        :ok -> File.chmod(level, 0o700) |> then(&{:cont, &1})
        {:error, :eexist} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp write_private(file, content) do
    temporary = file <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(temporary, content),
         :ok <- File.chmod(temporary, 0o600) do
      File.rename(temporary, file)
    end
  end
end
