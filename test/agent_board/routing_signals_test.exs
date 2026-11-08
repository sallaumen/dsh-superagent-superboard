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

    assert Signals.read(fn -> {:ok, state} end, fn -> %{} end) == %{
             "dsh" => %{
               repository: "sallaumen/arena-rogue",
               state: :ready,
               load: %{running: 0, queued: 0, max_workers: 3}
             },
             "claude" => %{state: :unknown},
             "codex" => %{state: :unknown}
           }

    assert %{"dsh" => %{state: :paused}} =
             Signals.read(fn -> {:ok, %{state | paused: true}} end, fn -> %{} end)
  end

  test "an orchestrator that does not answer is a reason, and the repository unknown" do
    assert %{
             "dsh" => %{
               repository: nil,
               state: {:unavailable, "o orquestrador respondeu HTTP 503"}
             }
           } =
             Signals.read(fn -> {:error, {:http, 503}} end, fn -> %{} end)
  end

  test "the ledger's expected cost joins each executor's signal" do
    costs = fn ->
      %{
        "dsh" => %{micros: 120_000, complete?: false},
        "claude" => %{micros: 300_000, complete?: true, reference: :list},
        "codex" => :unknown
      }
    end

    signals = Signals.read(fn -> {:error, :unreachable} end, costs)

    assert signals["dsh"][:cost] == %{micros: 120_000, complete?: false}
    assert signals["claude"][:cost] == %{micros: 300_000, complete?: true, reference: :list}
    # Unknown is not stored as a cost: the snapshot says nothing, and the
    # router shows "desconhecido".
    refute Map.has_key?(signals["codex"], :cost)
  end

  test "the snapshot is plain data" do
    signals = Signals.read(fn -> {:error, :unreachable} end, fn -> %{} end)

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
