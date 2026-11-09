defmodule AgentBoard.LogsTest do
  @moduledoc """
  The log reader: only warning/error lines, stack traces grouped, offsets
  respected, truncation handled and every boundary bounded.
  """
  use ExUnit.Case, async: false

  alias AgentBoard.Logs
  alias AgentBoard.Logs.Entry

  setup do
    dir = Path.join(System.tmp_dir!(), "agent-board-logs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    previous_log = Application.get_env(:agent_board, :log_path)
    previous_dir = Application.get_env(:agent_board, :superagent_log_dir)

    on_exit(fn ->
      restore(:log_path, previous_log)
      restore(:superagent_log_dir, previous_dir)
    end)

    {:ok, dir: dir}
  end

  defp restore(key, nil), do: Application.delete_env(:agent_board, key)
  defp restore(key, value), do: Application.put_env(:agent_board, key, value)

  defp board_source(path) do
    %{id: "board", kind: :board, label: "Agent Board", path: path}
  end

  defp superagent_source do
    %{
      id: "superagent:superagent",
      kind: :superagent,
      label: "Superagente superagent",
      path: "/tmp/x"
    }
  end

  defp write(path, lines), do: File.write!(path, Enum.join(lines, "\n") <> "\n")

  defp board_line(level, message), do: "2026-11-08 21:00:00.000 [#{level}] #{message}"

  test "boards keep only warning/error lines and group their continuation lines" do
    text = """
    2026-11-08 20:59:59.000 [info] GET /
    2026-11-08 21:00:00.000 [warning] first warning
    warning detail
    2026-11-08 21:00:01.000 [debug] this closes the group
    not a continuation after a timestamped line
    2026-11-08 21:00:02.000 [error] boom
    ** (RuntimeError) boom
        lib/agent_board/local_ci.ex:108: AgentBoard.LocalCI.workpad_state/2
    Process Label: {Phoenix.LiveView, AgentBoardWeb.BoardLive, "lv:1"}
    """

    assert [warning, error] = Logs.parse(board_source("/tmp/board.log"), text)

    assert %Entry{level: :warning, at: "2026-11-08 21:00:00.000", message: "first warning"} =
             warning

    assert warning.lines == ["warning detail"]

    assert error.level == :error
    assert error.message == "boom"

    assert error.lines == [
             "** (RuntimeError) boom",
             "    lib/agent_board/local_ci.ex:108: AgentBoard.LocalCI.workpad_state/2",
             ~s(Process Label: {Phoenix.LiveView, AgentBoardWeb.BoardLive, "lv:1"})
           ]
  end

  test "board lines without a timestamp before the first entry are ignored" do
    assert Logs.parse(board_source("/tmp/board.log"), "orphan line\n") == []
  end

  test "a continuation line longer than the display cap is clipped" do
    text = board_line("error", "x") <> "\n" <> String.duplicate("a", 2_100) <> "\n"

    assert [%Entry{lines: [line]}] = Logs.parse(board_source("/tmp/board.log"), text)
    assert String.length(line) == 2_001
    assert String.ends_with?(line, "…")
  end

  test "keepalive logs keep only lines that report a problem" do
    text = """
    2026-11-08T16:11:50-0300 status 2: the agent runs but needs a person; not restarting
      {"errors": {}, "health": {"github": "starting"}}
    2026-11-08T16:12:49-0300 start exited 0
    2026-11-08T16:13:00-0300 start exited 1
    2026-11-08T16:14:00-0300 no manager at /missing; set DSH_SUPERAGENT_HOME
    """

    assert [warning, exit_error, manager_error] = Logs.parse(superagent_source(), text)
    assert warning.level == :warning
    assert warning.message =~ "needs a person"
    assert warning.lines == [~s(  {"errors": {}, "health": {"github": "starting"}})]
    assert exit_error.level == :error
    assert exit_error.message == "start exited 1"
    assert manager_error.level == :error
  end

  test "the first read takes the recent tail and the next read only new bytes", %{dir: dir} do
    path = Path.join(dir, "board.log")
    source = board_source(path)
    write(path, [board_line("warning", "one")])

    first = Logs.read([source], Logs.empty_state())
    assert [%Entry{message: "one", seq: 1}] = first.entries
    assert first.statuses["board"] == :ok

    File.write!(path, board_line("warning", "two") <> "\n", [:append])

    second = Logs.read([source], first.state)
    assert [%Entry{message: "two", seq: 2}] = second.entries
    assert second.state.files["board"].offset > first.state.files["board"].offset

    third = Logs.read([source], second.state)
    assert third.entries == []
    assert third.statuses["board"] == :ok
  end

  test "the initial tail drops the partial first line", %{dir: dir} do
    path = Path.join(dir, "board.log")

    lines =
      for n <- 1..12, do: board_line("warning", "warning-#{n}-" <> String.duplicate("x", 30))

    write(path, lines)

    source = board_source(path)
    read = Logs.read([source], Logs.empty_state(), initial_bytes: 90)

    assert read.entries != []
    assert List.last(read.entries).message =~ "warning-12-"
    assert Enum.all?(read.entries, &Regex.match?(~r/\Awarning-\d+-x+\z/, &1.message))
    assert read.state.files["board"].offset == File.stat!(path).size
  end

  test "an incremental tick never reads more than its byte budget", %{dir: dir} do
    path = Path.join(dir, "board.log")
    write(path, [board_line("warning", "seed")])
    source = board_source(path)
    seed = Logs.read([source], Logs.empty_state())
    assert seed.state.files["board"].offset == File.stat!(path).size

    File.write!(
      path,
      Enum.map_join(1..80, "\n", &board_line("warning", "line-#{&1}")) <> "\n",
      [:append]
    )

    size = File.stat!(path).size
    first = Logs.read([source], seed.state, max_bytes: 120)

    assert first.entries != []
    assert first.state.files["board"].offset < size

    second = Logs.read([source], first.state, max_bytes: 120)
    assert second.state.files["board"].offset > first.state.files["board"].offset
  end

  test "a truncated file is read again from its new tail", %{dir: dir} do
    path = Path.join(dir, "board.log")
    source = board_source(path)
    write(path, [board_line("warning", "one"), board_line("warning", "two")])

    first = Logs.read([source], Logs.empty_state())
    assert length(first.entries) == 2

    File.write!(path, board_line("error", "after truncate") <> "\n")

    second = Logs.read([source], first.state)
    assert [%Entry{level: :error, message: "after truncate"}] = second.entries
  end

  test "a rotated file is read from the new file's tail", %{dir: dir} do
    path = Path.join(dir, "board.log")
    source = board_source(path)
    write(path, [board_line("warning", "old")])

    first = Logs.read([source], Logs.empty_state())

    rotated = path <> ".1"
    File.rename!(path, rotated)
    write(path, [board_line("error", "new file")])

    second = Logs.read([source], first.state)
    assert [%Entry{message: "new file"}] = second.entries
  end

  test "missing and unreadable sources are reported, never invented", %{dir: dir} do
    missing = Logs.read([board_source(Path.join(dir, "nope.log"))], Logs.empty_state())
    assert missing.entries == []
    assert missing.statuses["board"] == :missing

    directory = Path.join(dir, "a-directory")
    File.mkdir_p!(directory)

    unreadable = Logs.read([board_source(directory)], Logs.empty_state())
    assert unreadable.entries == []
    assert unreadable.statuses["board"] == :unreadable
  end

  test "the buffer keeps the newest entries only", %{dir: dir} do
    path = Path.join(dir, "board.log")
    write(path, for(n <- 1..5, do: board_line("warning", "w#{n}")))

    read = Logs.read([board_source(path)], Logs.empty_state())
    assert Enum.map(read.entries, & &1.message) == ["w1", "w2", "w3", "w4", "w5"]

    assert Enum.map(Logs.append([], read.entries, 3), & &1.message) == ["w3", "w4", "w5"]
    assert Logs.summary(read.entries) == "5 avisos · 0 erros"
    assert Logs.counts(read.entries) == %{warning: 5, error: 0}
  end

  test "sources come from config and registered profiles, never from a browser path", %{dir: dir} do
    Application.put_env(:agent_board, :log_path, Path.join(dir, "board.log"))
    Application.put_env(:agent_board, :superagent_log_dir, dir)

    sources =
      Logs.sources([
        %{profile: "superagent", repository: nil},
        %{profile: "superagent-colmex", repository: nil}
      ])

    assert [board, default, colmex] = sources
    assert board.id == "board"
    assert board.path == Path.join(dir, "board.log")
    assert default.id == "superagent:superagent"
    assert default.path == Path.join(dir, "dsh-superagent-keepalive.log")
    assert colmex.id == "superagent:superagent-colmex"
    assert colmex.path == Path.join(dir, "dsh-superagent-colmex-keepalive.log")

    assert Logs.sources([%{profile: "../../etc/passwd"}]) == [board]
    assert Logs.superagent_log_path("../escape") == nil
  end
end
