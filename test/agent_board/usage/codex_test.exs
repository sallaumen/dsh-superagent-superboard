defmodule AgentBoard.Usage.CodexTest do
  @moduledoc "What Codex spent, read from a synthetic thread database and rollouts shaped like its own."
  # Not async: one test empties the PATH to prove a missing zstd is an error.
  use ExUnit.Case, async: false

  alias AgentBoard.Usage.{Codex, Lines}

  @zstd System.find_executable("zstd")
  @secret "SEGREDO-DA-CONVERSA"
  @thread "01a1ab5d-868b-7992-8c07-03ac39510001"
  @other "01a0ea97-2494-7850-9084-adbaa0d7af83"

  setup do
    root = Path.join(System.tmp_dir!(), "codex-usage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  describe "read_rollout/1" do
    test "credits each UTC day with the growth of the cumulative total", %{root: root} do
      path =
        write(root, "2026/11/05/rollout-2026-11-05T07-59-55-#{@thread}.jsonl", [
          session_meta_line(),
          token_count_line("2026-11-05T23:00:00.000Z", total(1_000, 800, 50, 10)),
          # The same total again is a repeat, not a request.
          token_count_line("2026-11-05T23:00:01.000Z", total(1_000, 800, 50, 10)),
          token_count_line("2026-11-05T23:30:00.000Z", nil),
          token_count_line("2026-11-05T23:59:59.000Z", total(3_000, 2_500, 150, 30)),
          token_count_line("2026-11-06T00:00:01.000Z", total(3_500, 2_900, 300, 90)),
          ~s({"type":"event_msg","payload":{"type":"token_count"),
          ~s({"timestamp":"2026-11-06T10:00:00.000Z","type":"response_item","payload":{"type":"message","content":[{"text":"#{@secret}"}]}})
        ])

      assert {:ok, rollout} = Codex.read_rollout(path)
      assert rollout.thread_id == @thread
      assert rollout.skipped == 1
      assert rollout.total.total == 3_800
      assert rollout.total.input == 3_500 and rollout.total.cached_input == 2_900

      assert [nov5, nov6] = rollout.days
      assert {nov5.day, nov5.requests, nov5.total} == {~D[2026-11-05], 2, 3_150}

      assert {nov5.input, nov5.cached_input, nov5.output, nov5.reasoning} ==
               {3_000, 2_500, 150, 30}

      assert nov5.first_at == ~U[2026-11-05 23:00:00.000Z]
      assert nov5.last_at == ~U[2026-11-05 23:59:59.000Z]
      assert {nov6.day, nov6.requests, nov6.total, nov6.output} == {~D[2026-11-06], 1, 650, 150}

      assert rollout.days |> Enum.map(& &1.total) |> Enum.sum() == rollout.total.total
    end

    test "a total that goes down starts a new count", %{root: root} do
      path =
        write(root, "rollout-2026-11-05T07-59-55-#{@thread}.jsonl", [
          token_count_line("2026-11-05T10:00:00.000Z", total(1_000, 0, 100, 0)),
          token_count_line("2026-11-05T11:00:00.000Z", total(200, 0, 20, 0))
        ])

      assert {:ok, %{days: [day], total: %{total: 220}}} = Codex.read_rollout(path)
      assert day.total == 1_320 and day.requests == 2
    end

    test "keeps the last rate limits it read", %{root: root} do
      path =
        write(root, "rollout-2026-11-05T07-59-55-#{@thread}.jsonl", [
          token_count_line("2026-11-05T10:00:00.000Z", total(10, 0, 1, 0), rate_limits(80.0)),
          token_count_line("2026-11-05T11:00:00.000Z", total(20, 0, 2, 0), rate_limits(90.0)),
          token_count_line("2026-11-05T12:00:00.000Z", total(30, 0, 3, 0))
        ])

      assert {:ok, %{rate_limits: limits}} = Codex.read_rollout(path)
      assert limits.observed_at == ~U[2026-11-05 11:00:00.000Z]
      assert limits.limit_id == "codex"

      assert limits.primary == %{
               used_percent: 90.0,
               window_minutes: 10_080,
               resets_at: ~U[2026-11-11 13:46:01Z]
             }

      assert limits.secondary == nil
      assert limits.credits == %{has_credits: false, unlimited: false, balance: "0"}
    end

    @tag skip: is_nil(@zstd) && "zstd is not installed"
    test "reads an old zstd rollout the same way", %{root: root} do
      lines = [
        token_count_line("2026-10-01T10:00:00.000Z", total(500, 100, 50, 5)),
        # A line longer than one pipe read, to cross chunk boundaries.
        ~s({"type":"response_item","payload":{"type":"reasoning","encrypted_content":"#{String.duplicate("x", 300_000)}"}}),
        token_count_line("2026-10-01T11:00:00.000Z", total(900, 300, 90, 9))
      ]

      plain = write(root, "rollout-2026-10-01T09-29-34-#{@thread}.jsonl", lines)
      {_, 0} = System.cmd(@zstd, ["-q", "--rm", "-o", plain <> ".zst", plain])

      assert {:ok, rollout} = Codex.read_rollout(plain <> ".zst")
      assert rollout.thread_id == @thread
      assert rollout.total.total == 990
      assert [%{total: 990, requests: 2}] = rollout.days
    end

    test "a missing file is an error", %{root: root} do
      assert {:error, :enoent} = Codex.read_rollout(Path.join(root, "rollout-x.jsonl"))
      assert {:error, :enoent} = Codex.read_rollout(Path.join(root, "rollout-x.jsonl.zst"))
    end

    test "without zstd an old rollout is unreadable, not empty", %{root: root} do
      path = Path.join(root, "rollout-2026-10-01T09-29-34-#{@thread}.jsonl.zst")
      File.write!(path, "x")

      saved = System.get_env("PATH")
      System.put_env("PATH", root)
      on_exit(fn -> System.put_env("PATH", saved) end)

      assert {:error, :zstd_missing} = Codex.read_rollout(path)
    end
  end

  describe "rollouts/1 and thread_id/1" do
    test "finds plain and zstd rollouts and names their thread", %{root: root} do
      write(root, "2026/11/05/rollout-2026-11-05T07-59-55-#{@thread}.jsonl", [])
      write(root, "2026/10/01/rollout-2026-10-01T09-29-34-#{@thread}.jsonl.zst", [])
      write(root, "2026/10/01/notes.jsonl", [])

      assert root |> Codex.rollouts() |> Enum.map(&Path.relative_to(&1, root)) == [
               "2026/10/01/rollout-2026-10-01T09-29-34-#{@thread}.jsonl.zst",
               "2026/11/05/rollout-2026-11-05T07-59-55-#{@thread}.jsonl"
             ]

      assert Codex.thread_id("rollout-2026-10-01T09-29-34-#{@thread}.jsonl.zst") == @thread
      assert Codex.thread_id("notes.jsonl") == nil

      # A thread that continues in a second file names itself first.
      continued =
        "rollout-2026-09-28T21-36-08-#{@thread}_01a0ea97-2494-7850-9084-adbaa0d7af83.jsonl.zst"

      assert Codex.thread_id(continued) == @thread
    end
  end

  describe "read_thread/1 and segments/1" do
    test "a continued thread counts on from its first file's last total", %{root: root} do
      first =
        write(root, "2026/09/28/rollout-2026-09-28T07-48-49-#{@thread}.jsonl", [
          token_count_line("2026-09-28T10:00:00.000Z", total(1_000, 0, 50, 0)),
          token_count_line("2026-09-28T20:00:00.000Z", total(9_000, 0, 1_000, 0))
        ])

      second =
        write(root, "2026/09/28/rollout-2026-09-28T21-36-08-#{@thread}_#{@other}.jsonl", [
          token_count_line(
            "2026-09-29T00:36:00.000Z",
            total(9_500, 0, 1_100, 0),
            nil,
            total(500, 0, 100, 0)
          ),
          token_count_line("2026-09-29T10:00:00.000Z", total(20_000, 0, 2_000, 0))
        ])

      assert Codex.segments([second, first, Path.join(root, "notes.jsonl")]) == %{
               @thread => [first, second]
             }

      assert {:ok, rollout} = Codex.read_thread([first, second])
      assert rollout.thread_id == @thread
      assert rollout.total.total == 22_000
      assert [%{total: 10_000}, %{total: 12_000, requests: 2}] = rollout.days

      # Read alone, the second file would count the first one's tokens again.
      assert {:ok, %{days: [%{total: 22_000}]}} = Codex.read_rollout(second)
    end

    test "a continuation that forks from an earlier point counts only its own growth",
         %{root: root} do
      base =
        write(root, "rollout-2026-09-23T08-14-38-#{@thread}.jsonl", [
          token_count_line("2026-09-23T11:00:00.000Z", total(9_000, 0, 1_000, 0))
        ])

      fork = fn name, at, total, last ->
        write(root, "rollout-#{name}-#{@thread}_#{@other}.jsonl", [
          token_count_line(at, total, nil, last)
        ])
      end

      # Both continuations start below the base's last total (10,000).
      a =
        fork.(
          "2026-09-23T14-29-25",
          "2026-09-23T17:29:00.000Z",
          total(9_000, 0, 800, 0),
          total(250, 0, 50, 0)
        )

      b =
        fork.(
          "2026-09-23T14-51-25",
          "2026-09-23T17:51:00.000Z",
          total(9_100, 0, 800, 0),
          total(350, 0, 50, 0)
        )

      File.write!(
        b,
        token_count_line("2026-09-23T20:00:00.000Z", total(18_000, 0, 2_000, 0)) <> "\n",
        [:append]
      )

      assert {:ok, rollout} = Codex.read_thread([base, a, b])
      assert rollout.total.total == 20_000
      assert [%{total: total, requests: 4}] = rollout.days
      assert total == 10_000 + 300 + 400 + (20_000 - 9_900)
    end
  end

  describe "threads/1" do
    test "reads the named columns of every thread", %{root: root} do
      db = state_db(root)

      assert {:ok, [thread]} = Codex.threads(db)
      assert thread.id == @thread
      assert thread.tokens_used == 271_305_555
      assert thread.cwd == "/Users/me/projects/agent-board"
      assert thread.git_branch == "feat/x"
      assert thread.git_origin_url == "https://github.com/sallaumen/agent-board.git"
      assert thread.model == "gpt-6-sol"
      assert thread.source == "vscode"
      assert thread.archived == false
    end

    test "an absent database is an error", %{root: root} do
      assert {:error, :enoent} = Codex.threads(Path.join(root, "nope.sqlite"))
    end
  end

  describe "Lines.reduce/3" do
    test "hands every line once, without the newline, with or without a final one", %{root: root} do
      path = Path.join(root, "lines.jsonl")
      File.write!(path, "a\nbb\n\nccc")

      assert {:ok, lines} = Lines.reduce(path, [], &[&1 | &2])
      assert Enum.reverse(lines) == ["a", "bb", "", "ccc"]
    end
  end

  describe "privacy" do
    test "the thread query never touches a text column", %{root: root} do
      # In the fixture, reading title, preview, name or first_user_message
      # fails the whole query (`json('...')` on a non-JSON string).
      db = state_db(root)
      assert {:ok, [_thread]} = Codex.threads(db)

      for column <- ~w(title preview name first_user_message) do
        assert {:error, _} = select(db, "SELECT #{column} FROM threads")
      end

      refute Enum.any?(Codex.columns(), &(&1 in [:title, :preview, :name, :first_user_message]))
    end

    test "no conversation text reaches the rollout results", %{root: root} do
      path =
        write(root, "rollout-2026-11-05T07-59-55-#{@thread}.jsonl", [
          session_meta_line(),
          ~s({"timestamp":"2026-11-05T10:00:00.000Z","type":"event_msg","payload":{"type":"user_message","message":"#{@secret} token_count"}}),
          ~s({"timestamp":"2026-11-05T10:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":6},"last_token_usage":{"total_tokens":6}},"rate_limits":{"limit_id":"codex","limit_name":"#{@secret}","primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1794404761}},"note":"#{@secret}"}})
        ])

      assert {:ok, rollout} = Codex.read_rollout(path)
      assert rollout.total.total == 6
      refute inspect(rollout, limit: :infinity, printable_limit: :infinity) =~ @secret
    end

    test "the rollout reader names only metadata strings" do
      assert Codex.string_fields() ==
               ~w(balance limit_id plan_type rate_limit_reached_type timestamp type)

      source = File.read!("lib/agent_board/usage/codex.ex")

      for field <-
            ~w(title preview first_user_message name message content text base_instructions) do
        refute source =~ ~s("#{field}"), "the reader must not name the #{field} field"
      end
    end
  end

  defp write(root, relative, lines) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Enum.map_join(lines, "", &(&1 <> "\n")))
    path
  end

  defp total(input, cached, output, reasoning) do
    %{
      input_tokens: input,
      cached_input_tokens: cached,
      cache_write_input_tokens: 0,
      output_tokens: output,
      reasoning_output_tokens: reasoning,
      total_tokens: input + output
    }
  end

  defp token_count_line(timestamp, total, rate_limits \\ nil, last \\ nil) do
    info =
      if total,
        do: %{
          total_token_usage: total,
          last_token_usage: last || total,
          model_context_window: 400_000
        }

    Jason.encode!(%{
      timestamp: timestamp,
      type: "event_msg",
      payload: %{type: "token_count", info: info, rate_limits: rate_limits}
    })
  end

  defp rate_limits(used) do
    %{
      limit_id: "codex",
      limit_name: nil,
      primary: %{used_percent: used, window_minutes: 10_080, resets_at: 1_794_404_761},
      secondary: nil,
      credits: %{has_credits: false, unlimited: false, balance: "0"},
      plan_type: nil,
      rate_limit_reached_type: nil
    }
  end

  defp session_meta_line do
    Jason.encode!(%{
      timestamp: "2026-11-05T10:59:55.000Z",
      type: "session_meta",
      payload: %{
        id: @thread,
        cwd: "/Users/me/projects/agent-board",
        base_instructions: %{text: @secret},
        git: %{branch: "feat/x"}
      }
    })
  end

  # The real table has these text columns too; here a view makes reading
  # any of them fail, so a query that touches one cannot pass.
  defp state_db(root) do
    db = Path.join(root, "state_5.sqlite")
    {:ok, conn} = Exqlite.Sqlite3.open(db)

    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE threads_base (
        id TEXT, rollout_path TEXT, created_at INTEGER, updated_at INTEGER, source TEXT,
        thread_source TEXT, originator TEXT, model_provider TEXT, model TEXT,
        reasoning_effort TEXT, cwd TEXT, git_branch TEXT, git_sha TEXT, git_origin_url TEXT,
        cli_version TEXT, tokens_used INTEGER, archived INTEGER
      );
      INSERT INTO threads_base VALUES (
        '#{@thread}', '/Users/me/.codex/sessions/2026/11/05/rollout.jsonl', 1794038395,
        1794066000, 'vscode', 'user', 'Codex Desktop', 'openai', 'gpt-6-sol', 'xhigh',
        '/Users/me/projects/agent-board', 'feat/x', 'abc123',
        'https://github.com/sallaumen/agent-board.git', '0.166.0', 271305555, 0
      );
      CREATE VIEW threads AS
        SELECT *, json('#{@secret}') AS title, json('#{@secret}') AS preview,
               json('#{@secret}') AS name, json('#{@secret}') AS first_user_message
        FROM threads_base;
      """)

    :ok = Exqlite.Sqlite3.close(conn)
    db
  end

  defp select(db, sql) do
    {:ok, conn} = Exqlite.Sqlite3.open(db, mode: :readonly)

    try do
      with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql) do
        Exqlite.Sqlite3.fetch_all(conn, stmt)
      end
    after
      Exqlite.Sqlite3.close(conn)
    end
  end
end
