defmodule AgentBoard.AgentSignalTest do
  @moduledoc "A silence is the age of the newest observed signal, never a guess."
  use ExUnit.Case, async: true

  alias AgentBoard.AgentSignal

  @now ~U[2026-11-07 12:00:00Z]

  test "the newest of the ticket's own timestamps is the signal" do
    ticket = %{
      "started_at" => ~U[2026-11-07 11:00:00Z],
      "report_at" => ~U[2026-11-07 11:30:00Z],
      "idle_at" => nil
    }

    assert AgentSignal.last_signal(ticket) == {~U[2026-11-07 11:30:00Z], :report}

    assert AgentSignal.silence(ticket, @now) ==
             %{at: ~U[2026-11-07 11:30:00Z], source: :report, seconds: 1800}
  end

  test "an answer the worker read is a signal: it is alive since then" do
    ticket = %{
      "started_at" => ~U[2026-11-07 10:00:00Z],
      "report_at" => ~U[2026-11-07 10:05:00Z],
      "idle_at" => ~U[2026-11-07 10:05:00Z],
      "answered_at" => ~U[2026-11-07 11:50:00Z]
    }

    assert AgentSignal.last_signal(ticket) == {~U[2026-11-07 11:50:00Z], :answer}
  end

  test "a ticket that only started has its start as the signal" do
    ticket = %{"started_at" => ~U[2026-11-07 11:50:00Z]}

    assert AgentSignal.silence(ticket, @now) ==
             %{at: ~U[2026-11-07 11:50:00Z], source: :start, seconds: 600}
  end

  test "a worktree change newer than the report is the signal" do
    dir = worktree()
    at = ~U[2026-11-07 11:45:00Z]
    File.write!(Path.join(dir, "hud.ex"), "defmodule Hud do\nend\n")
    File.touch!(Path.join(dir, "hud.ex"), DateTime.to_unix(at))

    ticket = %{
      "report_at" => ~U[2026-11-07 11:30:00Z],
      "execution" => %{"directory" => dir}
    }

    assert AgentSignal.last_signal(ticket) == {at, :worktree}
  end

  test "a missing worktree is not a signal" do
    ticket = %{
      "report_at" => ~U[2026-11-07 11:30:00Z],
      "execution" => %{"directory" => "/does/not/exist"}
    }

    assert AgentSignal.last_signal(ticket) == {~U[2026-11-07 11:30:00Z], :report}
  end

  test "no timestamp at all is no silence" do
    assert AgentSignal.silence(%{}, @now) == nil
    assert AgentSignal.silence(nil, @now) == nil
  end

  test "silences are keyed by task number and skip tasks without a ticket" do
    tasks = [%{number: 1}, %{number: 2}]
    tickets = %{1 => %{"started_at" => ~U[2026-11-07 11:00:00Z]}}

    assert %{1 => %{seconds: 3600, source: :start}} = AgentSignal.silences(tasks, tickets, @now)
    refute Map.has_key?(AgentSignal.silences(tasks, tickets, @now), 2)
  end

  test "a silence is a stall only from the threshold on" do
    refute AgentSignal.stalled?(nil, 900)
    refute AgentSignal.stalled?(%{seconds: 899}, 900)
    assert AgentSignal.stalled?(%{seconds: 900}, 900)
    assert AgentSignal.stall_after() == 900
  end

  defp worktree do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agent-signal-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    {_, 0} = System.cmd("git", ["-C", dir, "init", "-q"], stderr_to_stdout: true)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
