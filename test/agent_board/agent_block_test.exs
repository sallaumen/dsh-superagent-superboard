defmodule AgentBoard.AgentBlockTest do
  @moduledoc "A failed ticket says what happened, what the board does and what is left to the owner."
  use ExUnit.Case, async: true

  alias AgentBoard.{AgentBlock, AgentState}
  alias AgentBoard.AutoRetry.Attempt

  @failed_at ~U[2026-11-07 17:10:00Z]
  @model "LlmError: DeepSeek Messages transport failed"
  @prepare "Error: The prepare command failed: fatal: unable to access " <>
             "'https://github.com/sallaumen/arena-rogue.git/': Could not resolve host: github.com"

  defp ticket(summary, history \\ [], latest \\ nil) do
    previous =
      for {{report, ended}, i} <- Enum.with_index(history) do
        %{
          "id" => "a#{i}",
          "state" => "ended",
          "createdAt" => "2026-11-07T17:00:00Z",
          "report" =>
            report && %{"state" => report, "summary" => @model, "at" => "2026-11-07T17:01:00Z"},
          "endedReason" => ended
        }
      end

    latest =
      latest ||
        %{
          "id" => "latest",
          "state" => "running",
          "report" => %{
            "state" => "failed",
            "summary" => summary,
            "at" => DateTime.to_iso8601(@failed_at)
          }
        }

    AgentState.normalize(%{
      "id" => "t1",
      "mandate" => %{"basis" => %{"scope" => %{"number" => 53}}},
      "execution" => %{"directory" => "/nonexistent/agent-block-test"},
      "assignments" => previous ++ [latest]
    })
  end

  # The reader is three hours behind UTC, as the owner is (the browser's getTimezoneOffset).
  defp explain(ticket, opts \\ []) do
    AgentBlock.explain(ticket, Keyword.merge([now: @failed_at, tz_offset: 180, agent: :up], opts))
  end

  # The assertions below are the original Portuguese; the English test sets its own locale.
  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
    :ok
  end

  test "the English board reads the block in English" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    block = explain(ticket(@model))

    assert block.headline == "Network failure calling the model"

    assert block.line ==
             "**Network failure calling the model.** Automatic retry at 14:11 (1 of 3)."

    assert block.system ==
             "The board asks for attempt 1 of 3 at 14:11, without you."

    assert block.action == "Nothing to do. To skip the wait, press Try now."
    assert block.retry == "Try now"
    assert [%{text: "failed: network failure calling the model"}] = block.attempts
  end

  test "a scheduled retry names the failure, the local time and the count" do
    block = explain(ticket(@model))

    assert block.state == :scheduled
    assert block.headline == "Falha de rede ao chamar o modelo"

    assert block.line ==
             "**Falha de rede ao chamar o modelo.** Nova tentativa automática às 14:11 (1 de 3)."

    assert block.action =~ "Nada a fazer"
    assert block.retry == "Tentar agora"
    assert block.error == @model
  end

  test "an overdue retry goes out in a moment; with the agent down it waits for it" do
    late = DateTime.add(@failed_at, 120, :second)

    assert explain(ticket(@model), now: late).line =~
             "Nova tentativa automática em instantes (1 de 3)."

    assert explain(ticket(@model), agent: :down).line =~
             "Nova tentativa automática quando o agente voltar (1 de 3)."
  end

  test "after three retries the owner decides, with the step to take" do
    block = explain(ticket(@prepare, List.duplicate({"failed", "retried"}, 3)))

    assert block.state == :exhausted

    assert block.line ==
             "**Sem rede ao preparar o worktree: o GitHub não resolveu.** " <>
               "As 3 tentativas automáticas falharam; tente de novo quando a rede voltar."

    assert block.retry == "Tentar de novo"
  end

  test "a failure that is not the network asks the owner to read the error" do
    block = explain(ticket("Tests failed: 3 failures in board_test.exs"))

    assert block.state == :needs_person
    assert block.line =~ "**O agente relatou uma falha.** Não parece falha de rede"
    assert block.system =~ "não tenta sozinho"
  end

  test "a prepare that left files says which folder to remove" do
    block = AgentBlock.explain(ticket(@prepare), now: @failed_at, leftover?: fn _dir -> true end)

    assert block.state == :needs_person
    assert block.action == "Apague /nonexistent/agent-block-test e toque em Tentar de novo."
  end

  test "a retry waiting for a worker needs nobody and offers no button" do
    pending = %{"id" => "next", "state" => "pending", "createdAt" => "2026-11-07T17:11:00Z"}
    block = explain(ticket(nil, [{"failed", "retried"}], pending))

    assert block.state == :queued
    assert block.line == "**Nova tentativa na fila.** Esperando um worker livre (1 de 3)."
    assert block.retry == nil
    assert block.error == @model
  end

  test "no block for a ticket that did not fail" do
    working = %{"id" => "w", "state" => "running", "report" => %{"state" => "progress"}}
    assert explain(ticket(nil, [], working)) == nil
    assert AgentBlock.explain(nil, []) == nil
  end

  test "the attempts tell the board's retries from a person's" do
    rows = [
      %Attempt{assignment_id: "a0", outcome: "retried", updated_at: ~U[2026-11-07 17:02:00Z]}
    ]

    history = [{"failed", "retried"}, {"failed", "retried"}]

    assert [first, second, third] =
             AgentBlock.attempts(ticket(@model, history), retries: rows, tz_offset: 180)

    assert first.text ==
             "falhou: falha de rede ao chamar o modelo; nova tentativa automática às 14:02"

    assert second.text == "falhou: falha de rede ao chamar o modelo; nova tentativa pedida"
    assert third.text == "falhou: falha de rede ao chamar o modelo"
    assert third.at == @failed_at
  end
end
