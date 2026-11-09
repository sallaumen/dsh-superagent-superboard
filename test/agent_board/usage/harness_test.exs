defmodule AgentBoard.Usage.HarnessTest do
  @moduledoc "What the coding agent's executor spent on a task, read from its local transcripts."
  use ExUnit.Case, async: false

  alias AgentBoard.Usage.Harness

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

      usage = Harness.parse(Enum.join(lines, "\n"))

      assert usage.requests == 2
      assert usage.input == 150
      assert usage.output == 15
      assert usage.cache_read == 3_000
      assert usage.cache_write == 7
      assert usage.model == "deepseek-flash"
      assert usage.subagent? == false
    end

    test "a session that switched models is unpriced, not priced at the last one" do
      lines = [
        session_line("worker-mixed", 0),
        ~s({"type":"model/selection","seq":1,"data":{"provider":"deepseek-account","model":"deepseek-flash"}}),
        assistant_line("m1", 100, 10, 0),
        ~s({"type":"model/selection","seq":3,"data":{"provider":"deepseek-account","model":"unlisted-model"}}),
        assistant_line("m2", 100, 10, 0)
      ]

      usage = Harness.parse(Enum.join(lines, "\n"))

      assert usage.model == nil
      assert Harness.cost([usage]) == nil
    end

    test "a delegated session is a subagent" do
      usage = Harness.parse(session_line("9d07fa0a", 1))
      assert usage.subagent? == true
      assert usage.requests == 0
    end
  end

  describe "transcript_dir/1" do
    test "encodes the ticket directory the way the harness names its session folder", %{
      root: root
    } do
      assert Harness.transcript_dir("/Users/me/.dsh/state/superagent/work/audio-1a2b") ==
               Path.join(root, "--Users-me-.dsh-state-superagent-work-audio-1a2b--")
    end
  end

  describe "cost/1" do
    test "prices input and output and says the total is a minimum when cache reads have no price" do
      cost =
        Harness.cost([
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
        Harness.cost([
          %{model: "deepseek-flash", input: 1_000_000, output: 0, cache_read: 0, cache_write: 0}
        ])

      assert cost == %{micros: 280_000, complete?: true}
    end

    test "an unpriced model is unknown, never zero" do
      assert Harness.cost([
               %{model: "mystery-1", input: 10, output: 10, cache_read: 0, cache_write: 0}
             ]) == nil
    end

    test "a priced session still counts beside an unpriced one, as a minimum" do
      cost =
        Harness.cost([
          %{model: "deepseek-flash", input: 1_000_000, output: 0, cache_read: 0, cache_write: 0},
          %{model: nil, input: 10, output: 10, cache_read: 0, cache_write: 0}
        ])

      assert cost == %{micros: 280_000, complete?: false}
    end
  end

  describe "for_tickets/2" do
    test "a ticket without transcripts has nothing to measure" do
      assert Harness.for_tickets([ticket("/nowhere/at-all")]).status == :none
      assert Harness.for_tickets([]).status == :none
    end

    @tag skip: is_nil(@zstd) && "zstd is not installed"
    test "adds the worker and its subagents and reuses an unchanged reading" do
      dir = "/tmp/work/menu-copy-5e09"
      folder = Harness.transcript_dir(dir)

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

      usage = Harness.for_tickets([ticket(dir)])

      assert usage.status == :measured
      assert usage.workers == 1
      assert usage.subagents == 1
      assert usage.requests == 2
      assert usage.input == 1_000_000
      assert usage.output == 1_000_000
      assert usage.cache_read == 10
      assert usage.models == ["deepseek-flash"]
      assert usage.cost == %{micros: 700_000, complete?: false}

      assert Harness.for_tickets([ticket(dir)], usage) == usage
    end

    test "without zstd the transcripts are unreadable, not empty", %{root: root} do
      folder = Path.join(root, "--tmp-work-x--")
      File.mkdir_p!(Path.join(folder, "worker-x"))
      File.write!(Path.join([folder, "worker-x", "session.v4.jsonl.zstd"]), "x")

      path = System.get_env("PATH")
      System.put_env("PATH", root)
      on_exit(fn -> System.put_env("PATH", path) end)

      usage = Harness.for_tickets([ticket("/tmp/work/x")])
      assert usage.status == :unavailable
      assert usage.reason == :zstd_missing
    end
  end

  describe "a time window" do
    test "parse counts only the messages sent inside it, end excluded" do
      lines = [
        ~s({"type":"model/selection","seq":1,"time":500,"data":{"model":"deepseek-flash"}}),
        timed(assistant_line("m1", 100, 10, 0), 1_000),
        timed(assistant_line("m2", 50, 5, 0), 5_000),
        timed(assistant_line("m3", 20, 2, 0), 9_000),
        assistant_line("untimed", 7, 7, 0)
      ]

      usage = Harness.parse(Enum.join(lines, "\n"), window: {2_000, 9_000})

      assert usage.requests == 1
      assert usage.input == 50
      assert usage.output == 5
      assert usage.model == "deepseek-flash"
    end

    @tag skip: is_nil(@zstd) && "zstd is not installed"
    test "window/2 reads every session changed since the start, the orchestrator's too", %{
      root: root
    } do
      since = ~U[2026-11-06 11:00:00Z]
      until = ~U[2026-11-07 11:00:00Z]
      inside = DateTime.to_unix(~U[2026-11-07 09:00:00Z], :millisecond)
      before = DateTime.to_unix(~U[2026-11-06 09:00:00Z], :millisecond)

      write_transcript(Path.join(root, "--Users-x-.dsh-state-superagent--"), "orchestrator-1", [
        ~s({"type":"model/selection","data":{"model":"deepseek-flash"}}),
        timed(assistant_line("o1", 1_000_000, 0, 0), inside),
        timed(assistant_line("o0", 5, 5, 0), before)
      ])

      write_transcript(Path.join(root, "--tmp-work-a--"), "worker-a", [
        ~s({"type":"model/selection","data":{"model":"deepseek-flash"}}),
        timed(assistant_line("w1", 0, 1_000_000, 0), inside)
      ])

      # A session nobody touched since the start is not decompressed.
      stale = Path.join(root, "--tmp-work-old--")
      write_transcript(stale, "worker-old", [timed(assistant_line("x", 9, 9, 0), inside)])
      old = stale |> Path.join("worker-old/session.v4.jsonl.zstd")
      File.touch!(old, ~U[2026-11-05 00:00:00Z] |> DateTime.to_unix())

      usage = Harness.window(since, until)

      assert usage.status == :measured
      assert usage.requests == 2
      assert usage.input == 1_000_000
      assert usage.output == 1_000_000
      assert usage.models == ["deepseek-flash"]
    end

    test "window/2 with no session changed has nothing to measure" do
      assert Harness.window(~U[2026-11-06 11:00:00Z], ~U[2026-11-07 11:00:00Z]).status ==
               :none
    end
  end

  defp timed(line, ms), do: line |> Jason.decode!() |> Map.put("time", ms) |> Jason.encode!()

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
