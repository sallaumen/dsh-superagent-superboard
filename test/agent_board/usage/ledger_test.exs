defmodule AgentBoard.Usage.LedgerTest do
  @moduledoc "The usage ledger: Claude Code, Codex and harness files read into one row per execution and day."
  # Not async: the readers' folders are application settings.
  use AgentBoard.DataCase, async: false

  # An unreadable file logs a warning; the tests assert the row instead.
  @moduletag :capture_log

  alias AgentBoard.Usage.{ClaudeCode, Harness, Ledger, Worker}

  @zstd System.find_executable("zstd")
  @thread "01a1ab5d-868b-7992-8c07-03ac39510001"
  @other "01a0ea97-2494-7850-9084-adbaa0d7af83"

  setup do
    root = Path.join(System.tmp_dir!(), "usage-ledger-#{System.unique_integer([:positive])}")

    dirs = %{
      claude: Path.join(root, "claude"),
      codex: Path.join(root, "codex"),
      dsh: Path.join(root, "dsh")
    }

    Enum.each(dirs, fn {_, dir} -> File.mkdir_p!(dir) end)

    settings = [
      claude_projects_dir: dirs.claude,
      codex_sessions_dir: dirs.codex,
      codex_state_db: Path.join(root, "state_5.sqlite"),
      codex_archived_dir: Path.join(root, "codex-archived"),
      dsh_sessions_dir: dirs.dsh
    ]

    saved = Enum.map(settings, fn {key, _} -> {key, Application.get_env(:agent_board, key)} end)
    Enum.each(settings, fn {key, value} -> Application.put_env(:agent_board, key, value) end)

    on_exit(fn ->
      File.rm_rf!(root)

      Enum.each(saved, fn
        {key, nil} -> Application.delete_env(:agent_board, key)
        {key, value} -> Application.put_env(:agent_board, key, value)
      end)
    end)

    Map.put(dirs, :root, root)
  end

  describe "Claude Code" do
    test "the ledger holds the reader's groups, each message once", %{claude: dir} do
      files = [
        write(dir, "p/parent.jsonl", [
          assistant("m1", "parent", "2026-11-06T23:00:00.000Z"),
          assistant("m1", "parent", "2026-11-06T23:00:00.000Z"),
          assistant("m2", "parent", "2026-11-07T01:00:00.000Z", branch: "fix/x")
        ]),
        write(dir, "p/fork.jsonl", [
          assistant("m1", "parent", "2026-11-06T23:00:00.000Z"),
          assistant("m3", "fork", "2026-11-07T02:00:00.000Z")
        ]),
        write(dir, "p/parent/subagents/agent-a.jsonl", [
          assistant("m4", "parent", "2026-11-07T03:00:00.000Z", model: "claude-fable-5-1")
        ])
      ]

      assert %{read: 3, failed: 0} = Ledger.refresh()

      expected =
        files
        |> ClaudeCode.messages()
        |> ClaudeCode.groups()
        |> Enum.map(
          &{&1.session_id, &1.day, &1.cwd, &1.git_branch, &1.model, &1.requests, &1.input,
           &1.output, &1.cache_read, &1.cache_write}
        )
        |> Enum.sort()

      assert ledger("claude_code") == expected
      assert Repo.aggregate("usage_messages", :count) == 4
    end

    test "reading the same files again changes no row", %{claude: dir, codex: codex} do
      write(dir, "p/s1.jsonl", [assistant("m1", "s1"), assistant("m2", "s1")])
      write(dir, "p/s2.jsonl", [assistant("m3", "s2")])
      codex_rollout(codex, [{"2026-11-05T10:00:00.000Z", 1_000, 800, 50}])
      state_db(400, 1_050)

      assert %{read: 3, failed: 0} = Ledger.refresh()
      before = snapshot()

      assert %{read: 0, rows: 0} = Ledger.refresh()

      # Every file looks changed: it is read again, and nothing moves.
      Repo.update_all("usage_files", set: [mtime: 0, offset: 0, fingerprint: nil])
      assert %{read: 3, rows: 0, failed: 0} = Ledger.refresh()
      assert snapshot() == before
    end

    test "a grown transcript is read from where it stopped; a new file appears in one run",
         %{claude: dir} do
      path =
        write(dir, "p/s1.jsonl", [assistant("m1", "s1", "2026-11-07T10:00:00.000Z", output: 3)])

      assert %{read: 1} = Ledger.refresh()

      # The rest of m1 (an older CLI's final count) and a new message.
      File.write!(
        path,
        Enum.map_join(
          [assistant("m1", "s1", "2026-11-07T10:00:00.000Z", output: 90), assistant("m2", "s1")],
          "",
          &(&1 <> "\n")
        ),
        [:append]
      )

      other = write(dir, "q/s2.jsonl", [assistant("m3", "s2")])

      assert %{read: 2, failed: 0} = Ledger.refresh()

      assert [{"s1", _, _, _, _, 2, 20, 190, _, _}, {"s2", _, _, _, _, 1, _, _, _, _}] =
               ledger("claude_code")

      assert file_row(path).offset == File.stat!(path).size
      assert file_row(other).offset == File.stat!(other).size

      expected = [path, other] |> ClaudeCode.messages() |> Enum.map(&{&1.id, &1.output})
      assert expected == [{"m1", 90}, {"m2", 100}, {"m3", 100}]
    end

    test "a rewritten transcript is read again from its start", %{claude: dir} do
      path = write(dir, "p/s1.jsonl", [assistant("m1", "s1")])
      assert %{read: 1} = Ledger.refresh()

      write(dir, "p/s1.jsonl", [
        assistant("m9", "s1"),
        assistant("m1", "s1"),
        assistant("m2", "s1")
      ])

      assert %{read: 1} = Ledger.refresh()

      assert [{"s1", _, _, _, _, 3, _, _, _, _}] = ledger("claude_code")
      assert file_row(path).offset == File.stat!(path).size
    end

    # Rows the ledger wrote before it knew the 1-hour writes hold zero there.
    # The file is read once more, in full, and its rows are filled.
    test "1-hour cache writes reach the ledger, also for a file read before the reader knew them",
         %{claude: dir} do
      write(dir, "p/s1.jsonl", [assistant("m1", "s1", "2026-11-07T10:00:00.000Z", write_1h: 30)])

      assert %{read: 1, failed: 0} = Ledger.refresh()
      assert one_hour_writes() == {[30], [30]}

      Repo.update_all("usage_messages", set: [cache_write_1h_tokens: 0])
      Repo.update_all("usage_ledger", set: [cache_write_1h_tokens: 0])
      Repo.update_all("usage_files", set: [reader: 1])

      assert %{read: 1, failed: 0} = Ledger.refresh()
      assert one_hour_writes() == {[30], [30]}
      assert %{read: 0} = Ledger.refresh()
    end

    test "a later copy of a message never counts twice nor moves it", %{claude: dir} do
      write(dir, "p/s1.jsonl", [assistant("m1", "s1"), assistant("m2", "s1")])
      assert %{read: 1} = Ledger.refresh()
      before = snapshot()

      # A moved session rewrites the sessionId on its copies.
      write(dir, "q/moved.jsonl", [assistant("m1", "moved"), assistant("m2", "moved")])
      assert %{read: 1, rows: 0} = Ledger.refresh()
      assert snapshot() == before
    end
  end

  describe "Codex" do
    test "a thread's days sum to its tokens_used, with the thread's cwd, branch and model",
         %{codex: dir} do
      codex_rollout(dir, [
        {"2026-11-05T23:00:00.000Z", 1_000, 800, 50},
        {"2026-11-05T23:59:00.000Z", 3_000, 2_500, 150},
        {"2026-11-06T00:01:00.000Z", 3_500, 2_900, 300}
      ])

      state_db(400, 3_800)

      assert %{read: 1, failed: 0} = Ledger.refresh()

      assert [
               {@thread, ~D[2026-11-05], "/w/agent-board", "feat/x", "gpt-6-sol", 2, 500, 150,
                2_500, 0},
               {@thread, ~D[2026-11-06], "/w/agent-board", "feat/x", "gpt-6-sol", 1, 100, 150,
                400, 0}
             ] = ledger("codex")

      tokens =
        "codex"
        |> ledger()
        |> Enum.map(fn {_, _, _, _, _, _, input, output, cache_read, _} ->
          input + output + cache_read
        end)
        |> Enum.sum()

      assert tokens == 3_800
    end

    test "a continued thread is one count, and an archived thread is read too",
         %{codex: dir, root: root} do
      codex_rollout(
        dir,
        [
          {"2026-09-28T10:00:00.000Z", 1_000, 0, 50},
          {"2026-09-28T20:00:00.000Z", 9_000, 0, 1_000}
        ],
        name: "2026/09/28/rollout-2026-09-28T07-48-49-#{@thread}.jsonl"
      )

      second =
        codex_rollout(dir, [{"2026-09-29T00:36:00.000Z", 9_500, 0, 1_100}],
          name: "2026/09/28/rollout-2026-09-28T21-36-08-#{@thread}_#{@other}.jsonl"
        )

      archived = "01a01f2b-d1ee-76f0-9866-f5cb744a584d"

      codex_rollout(
        Path.join(root, "codex-archived"),
        [{"2026-08-20T10:00:00.000Z", 500, 100, 20}],
        thread: archived,
        name: "rollout-2026-08-20T09-36-00-#{archived}.jsonl"
      )

      state_db(400, 10_600)

      assert %{read: 3, failed: 0} = Ledger.refresh()
      assert codex_tokens(@thread) == 10_600
      assert codex_tokens(archived) == 520

      # The continued file grows: both files are read again, as one count.
      File.write!(
        second,
        codex_line({"2026-09-29T05:00:00.000Z", 12_000, 0, 1_500}, []) <> "\n",
        [:append]
      )

      assert %{read: 2, failed: 0} = Ledger.refresh()
      assert codex_tokens(@thread) == 13_500
    end

    test "keeps the newest quota reading", %{codex: dir} do
      codex_rollout(dir, [{"2026-11-06T10:00:00.000Z", 10, 0, 1}], used: 90.0)
      state_db(400, 11)
      assert %{read: 1} = Ledger.refresh()

      older = "01a1ab5d-868b-7992-8c07-03ac39510002"

      codex_rollout(dir, [{"2026-11-05T10:00:00.000Z", 10, 0, 1}],
        used: 40.0,
        thread: older,
        name: "2026/11/05/rollout-2026-11-05T07-00-00-#{older}.jsonl"
      )

      assert %{read: 1} = Ledger.refresh()

      assert [limit] = Ledger.limits()
      assert limit.source == "codex" and limit.limit_id == "codex"
      assert limit.primary_used_percent == 90.0
      assert limit.primary_window_minutes == 10_080
      assert limit.execution_id == @thread
      assert limit.observed_at == ~U[2026-11-06 10:00:00.000000Z]
    end
  end

  describe "the harness" do
    @tag skip: is_nil(@zstd) && "zstd is not installed"
    test "a ticket's sessions are one execution, counted by Harness's parser", %{dsh: dir} do
      folder = "--Users-me-.dsh-state-superagent-work-audio-1a2b--"

      worker = [
        ~s({"type":"session","cwd":"/Users/me/.dsh/state/superagent/work/audio-1a2b","delegationDepth":0}),
        ~s({"type":"model/selection","seq":2,"time":1794072000000,"data":{"model":"deepseek-flash"}}),
        dsh_assistant("w1", 1_794_072_001_000, 100, 10),
        dsh_assistant("w1", 1_794_072_001_000, 100, 10),
        dsh_assistant("w2", 1_794_158_401_000, 50, 5)
      ]

      sub = [
        ~s({"type":"session","cwd":"/Users/me/.dsh/state/superagent/work/audio-1a2b","delegationDepth":1}),
        ~s({"type":"model/selection","seq":2,"time":1794072000000,"data":{"model":"deepseek-flash"}}),
        dsh_assistant("s1", 1_794_072_002_000, 7, 1)
      ]

      worker_path = dsh_session(dir, folder, "worker-1a2b", worker)
      sub_path = dsh_session(dir, folder, "9d07fa0a", sub)

      assert %{read: 2, failed: 0} = Ledger.refresh()

      assert [
               {^folder, ~D[2026-11-07], "/Users/me/.dsh/state/superagent/work/audio-1a2b", nil,
                "deepseek-flash", 2, 107, 11, _, _},
               {^folder, ~D[2026-11-08], _, nil, "deepseek-flash", 1, 50, 5, _, _}
             ] = ledger("dsh")

      {:ok, w} = Harness.read_file(worker_path)
      {:ok, s} = Harness.read_file(sub_path)
      parsed = Enum.map(w.messages ++ s.messages, & &1.input) |> Enum.sum()
      assert parsed == "dsh" |> ledger() |> Enum.map(&elem(&1, 6)) |> Enum.sum()
    end
  end

  describe "failures" do
    test "an unreadable file keeps its reason, the others are read, and it is tried again",
         %{claude: claude, codex: codex} do
      write(claude, "p/s1.jsonl", [assistant("m1", "s1")])
      broken = Path.join(codex, "2026/10/01/rollout-2026-10-01T09-29-34-#{@thread}.jsonl.zst")
      File.mkdir_p!(Path.dirname(broken))
      File.write!(broken, "not zstd")

      assert %{read: 1, failed: 1} = Ledger.refresh()
      assert file_row(broken).error =~ "zstd"
      assert [{"s1", _, _, _, _, 1, _, _, _, _}] = ledger("claude_code")

      assert %{read: 0, failed: 1} = Ledger.refresh()
    end
  end

  describe "daily/1 and the worker" do
    test "each source is its own row on the same day", %{claude: claude, codex: codex} do
      write(claude, "p/s1.jsonl", [assistant("m1", "s1", "2026-11-05T10:00:00.000Z")])
      codex_rollout(codex, [{"2026-11-05T10:00:00.000Z", 1_000, 800, 50}])
      state_db(400, 1_050)

      assert :ok = perform_job()

      assert [
               %{
                 source: "claude_code",
                 day: ~D[2026-11-05],
                 executions: 1,
                 requests: 1,
                 input_tokens: 10
               },
               %{
                 source: "codex",
                 day: ~D[2026-11-05],
                 executions: 1,
                 requests: 1,
                 input_tokens: 200,
                 cache_read_tokens: 800
               }
             ] = Ledger.daily(~D[2026-11-01])

      assert Ledger.daily(~D[2026-11-06]) == []
    end
  end

  defp perform_job, do: Worker.perform(%Oban.Job{args: %{}})

  defp ledger(source) do
    Repo.all(
      from l in "usage_ledger",
        where: l.source == ^source,
        order_by: [l.execution_id, l.day, l.cwd, l.git_branch, l.model],
        select:
          {l.execution_id, l.day, l.cwd, l.git_branch, l.model, l.requests, l.input_tokens,
           l.output_tokens, l.cache_read_tokens, l.cache_write_tokens}
    )
  end

  defp snapshot do
    %{
      ledger:
        Repo.all(
          from l in "usage_ledger",
            order_by: l.id,
            select:
              {l.id, l.source, l.execution_id, l.day, l.requests, l.input_tokens, l.output_tokens,
               l.updated_at}
        ),
      messages:
        Repo.all(
          from m in "usage_messages",
            order_by: m.id,
            select: {m.id, m.message_id, m.execution_id, m.input_tokens, m.output_tokens}
        )
    }
  end

  defp one_hour_writes do
    {Repo.all(from m in "usage_messages", select: m.cache_write_1h_tokens),
     Repo.all(from l in "usage_ledger", select: l.cache_write_1h_tokens)}
  end

  defp file_row(path) do
    Repo.one!(
      from f in "usage_files", where: f.path == ^path, select: %{offset: f.offset, error: f.error}
    )
  end

  defp write(root, relative, lines) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Enum.map_join(lines, "", &(&1 <> "\n")))
    path
  end

  defp assistant(id, session, timestamp \\ "2026-11-07T10:00:00.000Z", opts \\ []) do
    Jason.encode!(%{
      type: "assistant",
      sessionId: session,
      cwd: Keyword.get(opts, :cwd, "/w/repo"),
      gitBranch: Keyword.get(opts, :branch, "main"),
      timestamp: timestamp,
      message: %{
        id: id,
        model: Keyword.get(opts, :model, "claude-opus-5-5"),
        content: [%{type: "text", text: "nunca lido"}],
        usage: %{
          input_tokens: 10,
          output_tokens: Keyword.get(opts, :output, 100),
          cache_read_input_tokens: 1_000,
          cache_creation_input_tokens: 50,
          cache_creation: %{
            ephemeral_5m_input_tokens: 50 - Keyword.get(opts, :write_1h, 0),
            ephemeral_1h_input_tokens: Keyword.get(opts, :write_1h, 0)
          }
        }
      }
    })
  end

  defp codex_rollout(dir, points, opts \\ []) do
    thread = Keyword.get(opts, :thread, @thread)
    name = Keyword.get(opts, :name, "2026/11/05/rollout-2026-11-05T07-59-55-#{thread}.jsonl")

    write(dir, name, Enum.map(points, &codex_line(&1, opts)))
  end

  defp codex_line({at, input, cached, output}, opts) do
    Jason.encode!(%{
      timestamp: at,
      type: "event_msg",
      payload: %{
        type: "token_count",
        info: %{
          total_token_usage: %{
            input_tokens: input,
            cached_input_tokens: cached,
            output_tokens: output,
            reasoning_output_tokens: 0,
            total_tokens: input + output
          }
        },
        rate_limits: %{
          limit_id: "codex",
          primary: %{
            used_percent: Keyword.get(opts, :used, 50.0),
            window_minutes: 10_080,
            resets_at: 1_794_404_761
          },
          credits: %{has_credits: false, unlimited: false, balance: "0"}
        }
      }
    })
  end

  defp codex_tokens(thread) do
    Repo.one(
      from l in "usage_ledger",
        where: l.source == "codex" and l.execution_id == ^thread,
        select: type(sum(l.input_tokens + l.cache_read_tokens + l.output_tokens), :integer)
    )
  end

  defp state_db(created_at, tokens_used) do
    db = Application.fetch_env!(:agent_board, :codex_state_db)
    {:ok, conn} = Exqlite.Sqlite3.open(db)

    :ok =
      Exqlite.Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS threads (
        id TEXT, rollout_path TEXT, created_at INTEGER, updated_at INTEGER, source TEXT,
        thread_source TEXT, originator TEXT, model_provider TEXT, model TEXT,
        reasoning_effort TEXT, cwd TEXT, git_branch TEXT, git_sha TEXT, git_origin_url TEXT,
        cli_version TEXT, tokens_used INTEGER, archived INTEGER, title TEXT
      );
      INSERT INTO threads VALUES ('#{@thread}', 'rollout.jsonl', #{created_at}, #{created_at},
        'vscode', 'user', 'Codex Desktop', 'openai', 'gpt-6-sol', 'xhigh', '/w/agent-board',
        'feat/x', 'abc', 'https://github.com/sallaumen/agent-board.git', '0.166.0',
        #{tokens_used}, 0, 'nunca lido');
      """)

    :ok = Exqlite.Sqlite3.close(conn)
  end

  defp dsh_assistant(id, time, input, output) do
    Jason.encode!(%{
      type: "assistant/message",
      seq: 5,
      time: time,
      data: %{
        message: %{id: id, content: "nunca lido"},
        usage: %{
          inputTokens: input,
          outputTokens: output,
          cacheReadTokens: 1_000,
          cacheWriteTokens: 0
        }
      }
    })
  end

  defp dsh_session(dir, folder, session, lines) do
    plain = write(dir, Path.join([folder, session, "session.v4.jsonl"]), lines)
    {_, 0} = System.cmd(@zstd, ["-q", "--rm", "-o", plain <> ".zstd", plain])
    plain <> ".zstd"
  end
end
