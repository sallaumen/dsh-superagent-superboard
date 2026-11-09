defmodule AgentBoard.AI.Engines.Rehearsal do
  @moduledoc """
  The free fixture: answers every registered call without a model.

  It exists so the panel can be driven end to end -- refine, split, answer --
  with no key and no bill, in development. The answer is canned on purpose:
  a rehearsal that pretended to be a model would teach nothing.
  """

  @behaviour AgentBoard.AI.Engine

  alias AgentBoard.AI.{Request, Result}

  @fixtures %{
    refine_request: %{
      "goal" => "o board responde rápido e mostra o estado real",
      "constraints" => ["sem quebrar o sync", "sem inventar dados"],
      "non_goals" => ["refatorar o visual"],
      "risks" => ["o poller e o sync competem pelo mesmo dado"],
      "open_questions" => ["qual o volume de PRs por sync?"],
      "assumptions" => [],
      "ready" => true,
      "language" => "pt"
    },
    propose_tasks: %{
      "tasks" => [
        %{
          "title" => "Medir o tempo de resposta do board",
          "body" => "Instrumentar o load e o broadcast e registrar p95 antes de mexer.",
          "kind" => "bug",
          "acceptance" => ["p95 medido e registrado", "nenhum dado inventado"],
          "depends_on" => [],
          "size" => "S"
        },
        %{
          "title" => "Corrigir o gargalo medido",
          "body" => "Atacar a causa do p95 acima do alvo; uma mudança por PR.",
          "kind" => "bug",
          "acceptance" => ["p95 abaixo do alvo", "teste de regressão"],
          "depends_on" => [0],
          "size" => "M"
        }
      ]
    },
    suggest_unblock: %{
      "suggestions" => [
        "Responda com a decisão que você já tem e deixe a tarefa seguir; não espere um mapa que não existe.",
        "Abra uma tarefa separada para o pré-requisito e retome esta quando ela fechar."
      ]
    },
    answer_question: %{
      "answer" => "Modo de ensaio: esta é uma resposta de fixture, sem modelo."
    },
    answer_board_question: %{
      "answer" => "Modo de ensaio: nenhuma resposta foi gerada por um modelo."
    },
    voice_agent: %{
      "reply" => "Modo de ensaio: esta resposta não veio de um modelo.",
      "action" => "reply",
      "request" => "",
      "title" => "",
      "details" => [],
      "question" => "",
      "task_number" => 0,
      "repository" => "",
      "lookup" => "",
      "direct" => false
    },
    voice_explain: %{
      "reply" => "Modo de ensaio: esta resposta não veio de um modelo."
    },
    summarize_conversation: %{
      "summary" => "Modo de ensaio: resumo de fixture, sem modelo."
    }
  }

  @impl true
  def run(%Request{} = request) do
    case Map.get(@fixtures, request.name) do
      nil ->
        {:error, :no_fixture}

      json ->
        {:ok,
         %Result{
           text: Jason.encode!(json),
           json: json,
           input_tokens: 0,
           output_tokens: 0,
           duration_ms: 0,
           model: "rehearsal",
           engine: :rehearsal,
           parse_state: :complete
         }}
    end
  end

  @impl true
  def status, do: :rehearsal
end
