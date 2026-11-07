defmodule AgentBoard.ExecutorUsageTest do
  @moduledoc "What the coding agent's executor spent on a task, read from its local transcripts."
  use ExUnit.Case, async: false

  alias AgentBoard.ExecutorUsage

  @zstd System.find_executable("zstd")

  setup do
    root = Path.join(System.tmp_dir!(), "executor-usage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    previous = Application.get_env(:agent_board, :dsh_sessions_dir)
    Application.put_env(:agent_board, :dsh_sessions_dir, root)

    on_exit(fn ->
      File.rm_rf!(root)

      if previous,
        do: Application.put_env(:agent_board, :dsh_sessions_dir, previous),
        else: Application.delete_env(:agent_board, :dsh_sessions_dir)
    end)

    %{root: root}
  end

  describe "parse/1" do
    test "sums each assistant message once and names the session's model" do
      lines = [
        session_line("worker-abc", 0),
        ~s({"type":"model/selection","seq":3,"data":{"provider":"deepseek-account","model":"deepseek-flash"}}),
        assistant_line("m1", 100, 10, 1_000),
        assistant_line("m1", 100, 10, 1_000),
        assistant_line("m2", 50, 5, 2_000, 7),
        ~s({"type":"tool/call","seq":9,"data":{}}),
        "not json"
      ]

      usage = ExecutorUsage.parse(Enum.join(lines, "\n"))

      assert usage.requests == 2
      assert usage.input == 150
      assert usage.output == 15
      assert usage.cache_read == 3_000
      assert usage.cache_write == 7
      assert usage.model == "deepseek-flash"
      assert usage.subagent? == false
    end

    test "a delegated session is a subagent" do
      usage = ExecutorUsage.parse(session_line("9d07fa0a", 1))
      assert usage.subagent? == true
      assert usage.requests == 0
    end
  end

  describe "transcript_dir/1" do
    test "encodes the ticket directory the way the harness names its session folder", %{
      root: root
    } do
      assert ExecutorUsage.transcript_dir("/Users/me/.dsh/state/superagent/work/audio-1a2b") ==
               Path.join(root, "--Users-me-.dsh-state-superagent-work-audio-1a2b--")
    end
  end

  describe "cost/1" do
    test "prices input and output and says the total is a minimum when cache reads have no price" do
      cost =
        ExecutorUsage.cost([
          %{
            model: "deepseek-flash",
            input: 1_000_000,
            output: 1_000_000,
            cache_read: 5,
            cache_write: 0
          }
        ])

      assert cost.micros == 700_000
      assert cost.complete? == false
    end

    test "is complete when nothing needs an unknown price" do
      cost =
        ExecutorUsage.cost([
          %{model: "deepseek-flash", input: 1_000_000, output: 0, cache_read: 0, cache_write: 0}
        ])

      assert cost == %{micros: 280_000, complete?: true}
    end

    test "an unpriced model is unknown, never zero" do
      assert ExecutorUsage.cost([
               %{model: "mystery-1", input: 10, output: 10, cache_read: 0, cache_write: 0}
             ]) == nil
    end

    test "a priced session still counts beside an unpriced one, as a minimum" do
      cost =
        ExecutorUsage.cost([
          %{model: "deepseek-flash", input: 1_000_000, output: 0, cache_read: 0, cache_write: 0},
          %{model: nil, input: 10, output: 10, cache_read: 0, cache_write: 0}
        ])

      assert cost == %{micros: 280_000, complete?: false}
    end
  end

  describe "for_tickets/2" do
    test "a ticket without transcripts has nothing to measure" do
      assert ExecutorUsage.for_tickets([ticket("/nowhere/at-all")]).status == :none
      assert ExecutorUsage.for_tickets([]).status == :none
    end

    @tag skip: is_nil(@zstd) && "zstd is not installed"
    test "adds the worker and its subagents and reuses an unchanged reading" do
      dir = "/tmp/work/menu-copy-5e09"
      folder = ExecutorUsage.transcript_dir(dir)

      write_transcript(folder, "worker-5e09", [
        session_line("worker-5e09", 0),
        ~s({"type":"model/selection","data":{"model":"deepseek-flash"}}),
        assistant_line("a", 1_000_000, 0, 10)
      ])

      write_transcript(folder, "291f0f54", [
        session_line("291f0f54", 1),
        ~s({"type":"model/selection","data":{"model":"deepseek-flash"}}),
        assistant_line("b", 0, 1_000_000, 0)
      ])

      usage = ExecutorUsage.for_tickets([ticket(dir)])

      assert usage.status == :measured
      assert usage.workers == 1
      assert usage.subagents == 1
      assert usage.requests == 2
      assert usage.input == 1_000_000
      assert usage.output == 1_000_000
      assert usage.cache_read == 10
      assert usage.models == ["deepseek-flash"]
      assert usage.cost == %{micros: 700_000, complete?: false}

      assert ExecutorUsage.for_tickets([ticket(dir)], usage) == usage
    end

    test "without zstd the transcripts are unreadable, not empty", %{root: root} do
      folder = Path.join(root, "--tmp-work-x--")
      File.mkdir_p!(Path.join(folder, "worker-x"))
      File.write!(Path.join([folder, "worker-x", "session.v4.jsonl.zstd"]), "x")

      path = System.get_env("PATH")
      System.put_env("PATH", root)
      on_exit(fn -> System.put_env("PATH", path) end)

      usage = ExecutorUsage.for_tickets([ticket("/tmp/work/x")])
      assert usage.status == :unavailable
      assert usage.reason == :zstd_missing
    end
  end

  defp ticket(directory), do: %{"execution" => %{"directory" => directory}}

  defp session_line(id, depth),
    do: ~s({"type":"session","version":4,"id":"#{id}","delegationDepth":#{depth}})

  defp assistant_line(id, input, output, cache_read, cache_write \\ 0) do
    Jason.encode!(%{
      type: "assistant/message",
      data: %{
        turn: 1,
        message: %{id: id, role: "assistant", content: []},
        usage: %{
          inputTokens: input,
          outputTokens: output,
          cacheReadTokens: cache_read,
          cacheWriteTokens: cache_write,
          totalTokens: input + output + cache_read + cache_write
        }
      }
    })
  end

  defp write_transcript(folder, session, lines) do
    dir = Path.join(folder, session)
    File.mkdir_p!(dir)
    plain = Path.join(dir, "session.v4.jsonl")
    File.write!(plain, Enum.join(lines, "\n") <> "\n")
    {_, 0} = System.cmd(@zstd, ["-q", "--rm", "-o", plain <> ".zstd", plain])
  end
end
