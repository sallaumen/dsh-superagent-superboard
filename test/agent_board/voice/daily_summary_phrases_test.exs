defmodule AgentBoard.Voice.DailySummaryPhrasesTest do
  @moduledoc "The summary of the day, spoken from its stored facts by template: no model."
  use ExUnit.Case, async: true

  alias AgentBoard.Voice.Phrases

  defp content(overrides \\ %{}) do
    Map.merge(
      %{
        "merged" => %{"count" => 3, "items" => []},
        "needs" => %{"blocked" => 1, "waiting" => 2, "items" => []},
        "sync_errors" => 0,
        "retries" => %{"sent" => 3, "tasks" => 2, "not_accepted" => 0},
        "spend" => [
          %{
            "executor" => "deepseek",
            "status" => "measured",
            "currency" => "USD",
            "micros" => 1_234_567,
            "complete" => true
          },
          %{"executor" => "claude", "status" => "unknown", "reason" => "no_source"},
          %{"executor" => "codex", "status" => "unknown", "reason" => "no_source"}
        ]
      },
      overrides
    )
  end

  test "says the day in Portuguese, each executor apart" do
    assert Phrases.daily_summary("pt-BR", content()) ==
             "Resumo do dia: 3 PRs mesclados. 1 tarefa bloqueada e 2 outras esperam você. " <>
               "Tentei de novo sozinho 3 vezes, em 2 tarefas. " <>
               "O DeepSeek gastou cerca de 1,23 dólar. Claude e Codex ainda sem medição."
  end

  test "says the day in English" do
    assert Phrases.daily_summary("en-US", content()) ==
             "Daily summary: 3 PRs merged. 1 blocked task and 2 others are waiting for you. " <>
               "I retried 3 times on my own, on 2 tasks. " <>
               "DeepSeek spent about 1.23 dollars. Claude and Codex are not measured yet."
  end

  test "a quiet day is short and never invents work" do
    quiet =
      content(%{
        "merged" => %{"count" => 0, "items" => []},
        "needs" => %{"blocked" => 0, "waiting" => 0, "items" => []},
        "retries" => %{"sent" => 0, "tasks" => 0, "not_accepted" => 0},
        "spend" => [
          %{"executor" => "deepseek", "status" => "none"},
          %{"executor" => "claude", "status" => "unknown", "reason" => "no_source"},
          %{"executor" => "codex", "status" => "unknown", "reason" => "no_source"}
        ]
      })

    assert Phrases.daily_summary("pt-BR", quiet) ==
             "Resumo do dia: nenhum PR mesclado. Nada espera você. " <>
               "O DeepSeek não rodou. Claude e Codex ainda sem medição."
  end

  test "singulars, a minimum, sync failures and a waiting-only day" do
    day =
      content(%{
        "merged" => %{"count" => 1, "items" => []},
        "needs" => %{"blocked" => 0, "waiting" => 1, "items" => []},
        "sync_errors" => 2,
        "retries" => %{"sent" => 1, "tasks" => 1, "not_accepted" => 0},
        "spend" => [
          %{
            "executor" => "deepseek",
            "status" => "measured",
            "micros" => 2_500_000,
            "complete" => false
          },
          %{"executor" => "claude", "status" => "unknown"},
          %{"executor" => "codex", "status" => "unknown"}
        ]
      })

    assert Phrases.daily_summary("pt-BR", day) ==
             "Resumo do dia: 1 PR mesclado. 1 tarefa espera você. " <>
               "A sincronização falhou 2 vezes. Tentei de novo sozinho 1 vez. " <>
               "O DeepSeek gastou pelo menos 2,50 dólares. Claude e Codex ainda sem medição."
  end

  test "less than a cent and an unknown DeepSeek reading" do
    tiny = %{
      "executor" => "deepseek",
      "status" => "measured",
      "micros" => 4_000,
      "complete" => true
    }

    unknown = %{"executor" => "deepseek", "status" => "unknown", "reason" => "zstd_missing"}

    others = [
      %{"executor" => "claude", "status" => "unknown"},
      %{"executor" => "codex", "status" => "unknown"}
    ]

    assert Phrases.daily_summary("pt-BR", content(%{"spend" => [tiny | others]})) =~
             "O DeepSeek gastou menos de um centavo de dólar."

    assert Phrases.daily_summary("pt-BR", content(%{"spend" => [unknown | others]})) =~
             "O gasto do DeepSeek é desconhecido."
  end

  test "the list price is said as a reference, and Codex as a share of the weekly quota" do
    spend = [
      %{"executor" => "deepseek", "status" => "none"},
      %{
        "executor" => "claude",
        "status" => "measured",
        "currency" => "USD",
        "reference" => "list",
        "micros" => 3_000_000,
        "complete" => true
      },
      %{
        "executor" => "codex",
        "status" => "measured",
        "currency" => "quota",
        "percent" => 90.0
      }
    ]

    text = Phrases.daily_summary("pt-BR", content(%{"spend" => spend}))

    assert text =~ "O Claude gastou cerca de 3,00 dólares a preço de lista, que não é a fatura."
    assert text =~ "O Codex está em 90% da cota semanal."

    english = Phrases.daily_summary("en-US", content(%{"spend" => spend}))

    assert english =~ "Claude spent about 3.00 dollars at list price, which is not the bill."
    assert english =~ "Codex is at 90% of the weekly quota."
  end

  test "a measured Claude or Codex line is said in its own terms once a source exists" do
    spend = [
      %{"executor" => "deepseek", "status" => "none"},
      %{
        "executor" => "claude",
        "status" => "measured",
        "micros" => 3_000_000,
        "complete" => true
      },
      %{"executor" => "codex", "status" => "unknown"}
    ]

    text = Phrases.daily_summary("pt-BR", content(%{"spend" => spend}))

    assert text =~ "O Claude gastou cerca de 3,00 dólares."
    assert text =~ "Codex ainda sem medição."
  end
end
