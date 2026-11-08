defmodule AgentBoard.RoutingTest do
  @moduledoc "The router's rules in the plan's order (docs/research/alfred.md, 3.5): a suggestion with reasons."
  use ExUnit.Case, async: true

  alias AgentBoard.Routing

  @ready %{
    "dsh" => %{
      repository: "sallaumen/arena-rogue",
      state: :ready,
      load: %{running: 1, max_workers: 3}
    },
    "claude" => %{state: :unknown},
    "codex" => %{state: :unknown}
  }

  defp task(repository, attrs \\ %{}), do: Map.merge(%{repository: repository}, attrs)

  test "the runner's repository goes to the DeepSeek, which the board dispatches itself" do
    suggestion = Routing.suggest(task("sallaumen/arena-rogue"), @ready)

    assert suggestion.executor == "dsh"
    assert suggestion.mode == "suggest"
    assert [reason] = suggestion.reasons
    assert reason =~ "único que o board despacha sozinho"
    assert reason =~ "1 de 3 rodando"
    assert Enum.map(suggestion.alternatives, & &1.executor) == ["claude", "codex"]
    assert suggestion.ruled_out == []
  end

  test "another repository rules the DeepSeek out and says so" do
    suggestion = Routing.suggest(task("sallaumen/o_colmex", %{work_type: "ui"}), @ready)

    assert suggestion.executor == "claude"

    assert [%{executor: "dsh", reason: "o DeepSeek só atende o sallaumen/arena-rogue."}] =
             suggestion.ruled_out

    assert "O DeepSeek só atende o sallaumen/arena-rogue." in suggestion.reasons
    assert Enum.any?(suggestion.reasons, &(&1 =~ "vem antes do Codex na ordem fixa"))
    assert "A disponibilidade do Claude Code é desconhecida." in suggestion.reasons
    assert [%{executor: "codex"}] = suggestion.alternatives
  end

  test "a runner that watches both repositories serves both" do
    signals =
      put_in(@ready, ["dsh", :repositories], ["sallaumen/arena-rogue", "sallaumen/o_colmex"])

    suggestion = Routing.suggest(task("sallaumen/o_colmex"), signals)
    assert suggestion.executor == "dsh"
    assert suggestion.ruled_out == []
  end

  test "an unreadable runner stays the board's default, and says why" do
    signals = Map.put(@ready, "dsh", %{repository: nil, state: {:unavailable, "sem resposta"}})

    for repository <- ["sallaumen/arena-rogue", "sallaumen/o_colmex"] do
      suggestion = Routing.suggest(task(repository), signals)

      assert suggestion.executor == "dsh"
      assert suggestion.ruled_out == []
      assert [reason] = suggestion.reasons
      assert reason =~ "Não deu para ler qual repositório o DeepSeek atende (sem resposta)"
      assert reason =~ "só anda se ele vigiar este repositório"
    end
  end

  test "a paused runner is out" do
    signals = put_in(@ready, ["dsh", :state], :paused)
    suggestion = Routing.suggest(task("sallaumen/arena-rogue"), signals)

    assert suggestion.executor == "claude"
    assert "O DeepSeek está pausado." in suggestion.reasons
  end

  test "the owner's explicit choice decides" do
    suggestion = Routing.suggest(task("sallaumen/arena-rogue", %{requested: "codex"}), @ready)

    assert suggestion.executor == "codex"
    assert hd(suggestion.reasons) == "Você pediu o Codex."
    assert Enum.map(suggestion.alternatives, & &1.executor) == ["dsh", "claude"]
  end

  test "an explicit choice the hard restriction rules out is named, not followed" do
    suggestion = Routing.suggest(task("sallaumen/o_colmex", %{requested: "dsh"}), @ready)

    assert suggestion.executor == "claude"

    assert hd(suggestion.reasons) ==
             "Você pediu o DeepSeek, mas o DeepSeek só atende o sallaumen/arena-rogue."

    # The ruled-out reason is not repeated after the lead.
    assert Enum.count(suggestion.reasons, &(&1 =~ "só atende")) == 1
  end

  test "an unknown name is no choice" do
    assert Routing.suggest(task("sallaumen/arena-rogue", %{requested: "gpt"}), @ready).executor ==
             "dsh"
  end

  test "the expected cost is unknown without a usage ledger, and passed through when known" do
    assert Routing.suggest(task("sallaumen/arena-rogue"), @ready).cost == :unknown

    signals = put_in(@ready, ["dsh", :cost], %{micros: 120_000, complete?: false})

    assert Routing.suggest(task("sallaumen/arena-rogue"), signals).cost ==
             %{micros: 120_000, complete?: false}
  end

  test "an executor reported unavailable is out; when everyone is out there is no suggestion" do
    signals = %{
      "dsh" => %{repository: "sallaumen/arena-rogue", state: :paused},
      "claude" => %{state: {:unavailable, "sem login"}},
      "codex" => %{state: {:unavailable, "cota semanal esgotada"}}
    }

    suggestion = Routing.suggest(task("sallaumen/arena-rogue"), signals)

    assert suggestion.executor == nil
    assert suggestion.cost == :unknown
    assert "Nenhum executor pode receber a tarefa agora." in suggestion.reasons
    assert "O Codex não está disponível (cota semanal esgotada)." in suggestion.reasons
  end
end
