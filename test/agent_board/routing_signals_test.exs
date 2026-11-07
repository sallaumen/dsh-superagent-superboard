defmodule AgentBoard.RoutingSignalsTest do
  @moduledoc "What the router reads, and the snapshot a decision keeps."
  use ExUnit.Case, async: true

  alias AgentBoard.Routing.Signals

  test "the runner's state becomes its signal; Claude Code and Codex stay unknown" do
    state = %{
      repository: "sallaumen/arena-rogue",
      paused: false,
      load: %{running: 0, queued: 0, max_workers: 3}
    }

    assert Signals.read(fn -> {:ok, state} end) == %{
             "dsh" => %{
               repository: "sallaumen/arena-rogue",
               state: :ready,
               load: %{running: 0, queued: 0, max_workers: 3}
             },
             "claude" => %{state: :unknown},
             "codex" => %{state: :unknown}
           }

    assert %{"dsh" => %{state: :paused}} =
             Signals.read(fn -> {:ok, %{state | paused: true}} end)
  end

  test "an orchestrator that does not answer is a reason, and the repository unknown" do
    assert %{
             "dsh" => %{
               repository: nil,
               state: {:unavailable, "o orquestrador respondeu HTTP 503"}
             }
           } =
             Signals.read(fn -> {:error, {:http, 503}} end)
  end

  test "the snapshot is plain data" do
    signals = Signals.read(fn -> {:error, :unreachable} end)

    assert Signals.snapshot(signals) == %{
             "dsh" => %{
               "repository" => nil,
               "state" => "unavailable: o orquestrador não respondeu"
             },
             "claude" => %{"state" => "unknown"},
             "codex" => %{"state" => "unknown"}
           }

    assert Jason.encode!(Signals.snapshot(signals))
  end
end
