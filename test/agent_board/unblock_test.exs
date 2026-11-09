defmodule AgentBoard.UnblockTest do
  @moduledoc "The words and request for unblocking a task, without a database."
  use ExUnit.Case, async: true

  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.Unblock

  @workpad """
  ## Relatório do agente

  ### Plano
  Esperar a decisão.

  ### Pergunta
  Como o app não tem perfis, devo entregar o menu restrito ao operador?

  ### Bloqueio
  O mapa da #1416 ainda não foi entregue.
  """

  @task %Task{
    id: 7,
    number: 1417,
    title: "Menu central do Ateliê",
    url: "https://github.com/sallaumen/arena-rogue/issues/1417"
  }
  @repo %Repository{id: 1, owner: "sallaumen", name: "arena-rogue"}

  test "reads the newest workpad that states a question or a blockage" do
    comments = [
      %{body: "plain comment", inserted_at: ~U[2026-11-09 07:00:00Z]},
      %{body: @workpad, inserted_at: ~U[2026-11-09 08:00:00Z]}
    ]

    assert %{question: question, blockage: blockage} = Unblock.context(comments)
    assert question =~ "menu restrito"
    assert blockage =~ "#1416"
  end

  test "a workpad with empty sections is not an unblock" do
    empty = "## Relatório do agente\n\n### Pergunta\n\n### Bloqueio\n"

    refute Unblock.context([%{body: empty, inserted_at: DateTime.utc_now()}])
  end

  test "a later reply to the agent resolves the old workpad, and a new workpad reopens it" do
    workpad = %{kind: "agent", body: @workpad, inserted_at: ~U[2026-11-09 08:00:00Z]}

    reply = %{
      kind: "user",
      body: "Use o menu restrito.\n\n@sallaumen-agent",
      inserted_at: ~U[2026-11-09 08:01:00Z]
    }

    refute Unblock.context([workpad, reply])

    next_workpad = %{workpad | inserted_at: ~U[2026-11-09 08:02:00Z]}
    assert %{question: question} = Unblock.context([workpad, reply, next_workpad])
    assert question =~ "menu restrito"
  end

  test "a same-second reply resolves the workpad using local comment order" do
    at = ~U[2026-11-09 08:00:00Z]
    workpad = %{id: 10, kind: "agent", body: @workpad, inserted_at: at}
    reply = %{id: 11, kind: "user", body: "Sim.\n\n@sallaumen-agent", inserted_at: at}

    refute Unblock.context([workpad, reply])
    assert Unblock.context([%{reply | id: 9}, workpad])
  end

  test "an earlier reply or a later unrelated comment does not resolve the workpad" do
    workpad = %{kind: "agent", body: @workpad, inserted_at: ~U[2026-11-09 08:00:00Z]}

    earlier_reply = %{
      kind: "user",
      body: "Outra decisão.\n\n@sallaumen-agent",
      inserted_at: ~U[2026-11-09 07:59:00Z]
    }

    unrelated = %{
      kind: "user",
      body: "Anotei um detalhe sem chamar o agente.",
      inserted_at: ~U[2026-11-09 08:01:00Z]
    }

    assert %{question: question} = Unblock.context([earlier_reply, workpad, unrelated])
    assert question =~ "menu restrito"
  end

  test "the title names the blocked issue and the body links back to it" do
    context = Unblock.context([%{body: @workpad, inserted_at: DateTime.utc_now()}])
    title = Unblock.blocker_title(@task, context)
    body = Unblock.blocker_body(@task, context)

    assert title =~ "Desbloquear #1417"
    assert body =~ "Desbloqueia #1417"
    assert body =~ "menu restrito"
    assert body =~ "#1416"
    assert body =~ "Critérios de aceite"
  end

  test "the request is linked to the blocked task and routed to the runner" do
    request = Unblock.request(@repo, @task, "Desbloquear #1417", "corpo")

    assert request.executor == "dsh"
    assert request.origin_task_id == @task.id
    assert request.blocker_for_task_id == @task.id
    assert is_binary(request.key)
    assert String.length(request.key) == 40
  end

  test "the AI inputs carry only the facts the prompt should see" do
    context = Unblock.context([%{body: @workpad, inserted_at: DateTime.utc_now()}])
    inputs = Unblock.ai_inputs(@task, @repo, context)

    assert inputs["issue"] == 1417
    assert inputs["repository"] == "sallaumen/arena-rogue"
    assert inputs["question"] =~ "menu restrito"
    assert inputs["blockage"] =~ "#1416"
  end
end
