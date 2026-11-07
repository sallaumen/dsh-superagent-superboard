defmodule AgentBoard.Usage.ClaudeCodeTest do
  @moduledoc "What Claude Code spent, read from synthetic transcripts shaped like its own."
  use ExUnit.Case, async: true

  alias AgentBoard.Usage.{ClaudeCode, Fields}

  @secret "SEGREDO-DA-CONVERSA"

  setup do
    root = Path.join(System.tmp_dir!(), "claude-usage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  describe "read_file/1" do
    test "counts a streamed message once, with the final count of every block", %{root: root} do
      path =
        write(root, "proj/s1.jsonl", [
          user_line("s1"),
          # Older CLIs wrote a partial output_tokens on the earlier blocks.
          assistant_line("m1", "s1", output: 3),
          assistant_line("m1", "s1", output: 120),
          assistant_line("m1", "s1", output: 120),
          assistant_line("m2", "s1", input: 7, cache_read: 900, cache_write: 40)
        ])

      assert {:ok, %{messages: [m1, m2], skipped: 0}} = ClaudeCode.read_file(path)
      assert m1.id == "m1" and m1.output == 120 and m1.input == 10
      assert m2.cache_read == 900 and m2.cache_write == 40 and m2.input == 7
    end

    test "skips synthetic messages and counts the lines it cannot read", %{root: root} do
      path =
        write(root, "proj/s1.jsonl", [
          assistant_line("m1", "s1", model: "<synthetic>"),
          ~s({"type":"assistant","message":{"id":"broken"),
          assistant_line("m2", "s1", timestamp: nil),
          assistant_line("m3", "s1")
        ])

      assert {:ok, %{messages: [%{id: "m3"}], skipped: 2}} = ClaudeCode.read_file(path)
    end

    test "a missing file is an error, not an empty transcript", %{root: root} do
      assert {:error, :enoent} = ClaudeCode.read_file(Path.join(root, "nope.jsonl"))
    end
  end

  describe "messages/1" do
    test "dedupes across files and keeps the session of the first copy", %{root: root} do
      parent =
        write(root, "proj/parent.jsonl", [
          assistant_line("m1", "parent"),
          assistant_line("m2", "parent")
        ])

      # A fork copies the parent's lines, keeping their sessionId, then adds its own.
      fork =
        write(root, "proj/fork.jsonl", [
          assistant_line("m1", "parent"),
          assistant_line("m2", "parent"),
          assistant_line("m3", "fork")
        ])

      # A subagent writes under the parent's sessionId in its own file.
      subagent =
        write(root, "proj/parent/subagents/agent-a1.jsonl", [assistant_line("m4", "parent")])

      # A moved session rewrites the sessionId on its copies: the first copy read wins.
      moved = write(root, "other/moved.jsonl", [assistant_line("m1", "moved")])

      messages = ClaudeCode.messages([parent, fork, subagent, moved])

      assert Enum.map(messages, &{&1.id, &1.session_id}) == [
               {"m1", "parent"},
               {"m2", "parent"},
               {"m3", "fork"},
               {"m4", "parent"}
             ]
    end

    test "merges the counts of copies by their largest value", %{root: root} do
      a = write(root, "a/s.jsonl", [assistant_line("m1", "s", output: 5)])
      b = write(root, "b/s.jsonl", [assistant_line("m1", "s", output: 80)])

      assert [%{output: 80}] = ClaudeCode.messages([a, b])
      assert [%{output: 80}] = ClaudeCode.messages([b, a])
    end
  end

  describe "groups/1" do
    test "groups by session, UTC day, cwd, branch and model", %{root: root} do
      path =
        write(root, "proj/s1.jsonl", [
          assistant_line("m1", "s1", timestamp: "2026-11-06T23:59:59.000Z", output: 1),
          assistant_line("m2", "s1", timestamp: "2026-11-07T00:00:01.000Z", output: 2),
          assistant_line("m3", "s1", timestamp: "2026-11-07T10:00:00.000Z", output: 4),
          assistant_line("m4", "s1", timestamp: "2026-11-07T11:00:00.000Z", branch: "fix/x"),
          assistant_line("m5", "s1", timestamp: "2026-11-07T12:00:00.000Z", cwd: "/w/other"),
          assistant_line("m6", "s1",
            timestamp: "2026-11-07T13:00:00.000Z",
            model: "claude-fable-5-1"
          )
        ])

      groups = path |> List.wrap() |> ClaudeCode.messages() |> ClaudeCode.groups()

      assert [nov6, nov7_fable, nov7_fix, nov7_other, nov7_main] =
               Enum.sort_by(groups, &{&1.day, &1.model, &1.git_branch, &1.cwd}, :asc)

      assert {nov6.day, nov6.requests, nov6.output} == {~D[2026-11-06], 1, 1}

      assert {nov7_main.day, nov7_main.git_branch, nov7_main.cwd, nov7_main.requests,
              nov7_main.output} ==
               {~D[2026-11-07], "main", "/w/repo", 2, 6}

      assert nov7_main.first_at == ~U[2026-11-07 00:00:01.000Z]
      assert nov7_main.last_at == ~U[2026-11-07 10:00:00.000Z]
      assert {nov7_fix.git_branch, nov7_fix.requests} == {"fix/x", 1}
      assert {nov7_other.cwd, nov7_other.requests} == {"/w/other", 1}
      assert {nov7_fable.model, nov7_fable.requests} == {"claude-fable-5-1", 1}
      assert Enum.all?(groups, &(&1.session_id == "s1"))
    end
  end

  describe "cost_states/1" do
    test "the deduped messages of a process match its last cost-state", %{root: root} do
      path =
        write(root, "proj/s1.jsonl", [
          assistant_line("m1", "s1", input: 10, output: 100, cache_read: 1_000, cache_write: 50),
          assistant_line("m1", "s1", input: 10, output: 100, cache_read: 1_000, cache_write: 50),
          cost_state_line("s1", 1, 0.5, %{in: 10, out: 100, cr: 1_000, cw: 50}),
          assistant_line("m2", "s1", input: 5, output: 20, cache_read: 300, cache_write: 0),
          cost_state_line("s1", 1, 0.7, %{in: 15, out: 120, cr: 1_300, cw: 50})
        ])

      assert [state] = ClaudeCode.cost_states([path])
      assert state.session_id == "s1" and state.start_time == 1 and state.cost_usd == 0.7

      totals =
        [path]
        |> ClaudeCode.messages()
        |> Enum.reduce(%{input: 0, output: 0, cache_read: 0, cache_write: 0}, fn m, acc ->
          %{
            input: acc.input + m.input,
            output: acc.output + m.output,
            cache_read: acc.cache_read + m.cache_read,
            cache_write: acc.cache_write + m.cache_write
          }
        end)

      assert Map.delete(state.models["claude-opus-5-5"], :cost_usd) == totals
    end
  end

  describe "transcripts/1" do
    test "finds sessions, subagents and workflow agents", %{root: root} do
      write(root, "p/s.jsonl", [])
      write(root, "p/s/subagents/agent-1.jsonl", [])
      write(root, "p/s/subagents/workflows/wf_1/agent-2.jsonl", [])
      write(root, "p/s/subagents/agent-1.meta.json", [])

      assert root |> ClaudeCode.transcripts() |> Enum.map(&Path.relative_to(&1, root)) == [
               "p/s.jsonl",
               "p/s/subagents/agent-1.jsonl",
               "p/s/subagents/workflows/wf_1/agent-2.jsonl"
             ]
    end
  end

  describe "privacy" do
    test "no conversation text reaches the reader's results", %{root: root} do
      path =
        write(root, "proj/s1.jsonl", [
          ~s({"type":"custom-title","customTitle":"#{@secret}","sessionId":"s1"}),
          ~s({"type":"last-prompt","lastPrompt":"#{@secret}","sessionId":"s1"}),
          ~s({"type":"summary","summary":"#{@secret}","leafUuid":"u"}),
          user_line("s1"),
          assistant_line("m1", "s1"),
          ~s({"type":"assistant","message":{"id":"m2","model":"claude-opus-5-5","role":"assistant","stop_reason":"#{@secret}","content":"#{@secret}","usage":{"input_tokens":1,"service_tier":"#{@secret}"}},"sessionId":"s1","cwd":"/w/repo","gitBranch":"main","timestamp":"2026-11-07T10:00:00.000Z","toolUseResult":{"stdout":"#{@secret}","lines":3}}),
          cost_state_line("s1", 1, 0.1, %{in: 1, out: 1, cr: 0, cw: 0})
        ])

      results = [
        ClaudeCode.read_file(path),
        ClaudeCode.messages([path]),
        [path] |> ClaudeCode.messages() |> ClaudeCode.groups(),
        ClaudeCode.cost_states([path])
      ]

      refute inspect(results, limit: :infinity, printable_limit: :infinity) =~ @secret
      assert [%{id: "m1"}, %{id: "m2", input: 1}] = ClaudeCode.messages([path])
    end

    test "the decoder drops content, arrays and unnamed strings while parsing" do
      line = assistant_line("m1", "s1")

      assert {:ok, event} = Fields.decode(line, MapSet.new(ClaudeCode.string_fields()))
      refute Map.has_key?(event["message"], "content")
      refute Map.has_key?(event["message"], "role")
      refute inspect(event) =~ @secret
      assert event["message"]["usage"]["output_tokens"] == 100
    end

    test "the reader names only metadata strings and never a text field" do
      assert ClaudeCode.string_fields() ==
               ~w(cwd gitBranch id model sessionId timestamp type)

      source = File.read!("lib/agent_board/usage/claude_code.ex")

      for field <- ~w(content customTitle lastPrompt summary text thinking input prompt) do
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

  defp user_line(session) do
    Jason.encode!(%{
      type: "user",
      sessionId: session,
      timestamp: "2026-11-07T09:59:00.000Z",
      message: %{role: "user", content: [%{type: "text", text: @secret}]}
    })
  end

  defp assistant_line(id, session, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, "2026-11-07T10:00:00.000Z")

    event = %{
      type: "assistant",
      sessionId: session,
      cwd: Keyword.get(opts, :cwd, "/w/repo"),
      gitBranch: Keyword.get(opts, :branch, "main"),
      isSidechain: false,
      uuid: "u-#{id}",
      message: %{
        id: id,
        model: Keyword.get(opts, :model, "claude-opus-5-5"),
        role: "assistant",
        content: [
          %{type: "thinking", thinking: @secret},
          %{type: "text", text: @secret},
          %{type: "tool_use", id: "t1", name: "Bash", input: %{command: @secret}}
        ],
        usage: %{
          input_tokens: Keyword.get(opts, :input, 10),
          output_tokens: Keyword.get(opts, :output, 100),
          cache_read_input_tokens: Keyword.get(opts, :cache_read, 1_000),
          cache_creation_input_tokens: Keyword.get(opts, :cache_write, 50),
          cache_creation: %{ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 50},
          service_tier: "standard",
          iterations: [%{input_tokens: 10, type: "message"}]
        }
      }
    }

    event = if timestamp, do: Map.put(event, :timestamp, timestamp), else: event
    Jason.encode!(event)
  end

  defp cost_state_line(session, start_time, cost, usage) do
    Jason.encode!(%{
      type: "cost-state",
      sessionId: session,
      startTime: start_time,
      totalCostUSD: cost,
      hasUnknownModelCost: false,
      modelUsage: %{
        "claude-opus-5-5" => %{
          inputTokens: usage.in,
          outputTokens: usage.out,
          cacheReadInputTokens: usage.cr,
          cacheCreationInputTokens: usage.cw,
          costUSD: cost
        }
      }
    })
  end
end
