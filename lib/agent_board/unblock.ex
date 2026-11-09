defmodule AgentBoard.Unblock do
  @moduledoc """
  The words and the request for unblocking a task the agent stopped on.

  A workpad says the question or the blockage; this module turns that into
  two useful choices for the owner: an answer to send (the AI suggestion
  fills the same draft) and a linked issue for the prerequisite the agent
  cannot provide itself. Pure; the caller owns the write and the gate.
  """

  alias AgentBoard.{Board, Workpad}
  alias AgentBoard.Board.{Repository, Task}

  @typedoc "The question and/or blockage the newest workpad states."
  @type context :: %{
          question: String.t() | nil,
          blockage: String.t() | nil,
          comment_at: DateTime.t() | nil
        }

  @doc """
  The newest workpad with a question or a blockage, or nil.

  Comments are the board's rows (maps or structs); `:body` and `:inserted_at`
  are the only fields read. An empty section is not a block.
  """
  @spec context([map()]) :: context() | nil
  def context(comments) when is_list(comments) do
    comments
    |> Enum.map(fn comment ->
      body = Map.get(comment, :body) || Map.get(comment, "body")
      {Workpad.parse(body), Map.get(comment, :inserted_at) || Map.get(comment, "inserted_at")}
    end)
    |> Enum.filter(fn
      {%{question: question, blockage: blockage}, _at} ->
        is_binary(question) or is_binary(blockage)

      _other ->
        false
    end)
    |> Enum.max_by(fn {_workpad, at} -> at || ~U[1970-01-01 00:00:00Z] end, fn -> nil end)
    |> case do
      nil ->
        nil

      {workpad, at} ->
        %{question: workpad.question, blockage: workpad.blockage, comment_at: at}
    end
  end

  def context(_comments), do: nil

  @doc "A short, editable title for the prerequisite issue."
  @spec blocker_title(Task.t(), context()) :: String.t()
  def blocker_title(task, context) do
    source = first_sentence(context.question || context.blockage || "pré-requisito")
    "Desbloquear ##{task.number}: #{String.slice(source, 0, 72)}"
  end

  @doc "The issue body: what blocked the agent, the decision it needs and the link back."
  @spec blocker_body(Task.t(), context(), DateTime.t() | nil) :: String.t()
  def blocker_body(task, context, _now \\ nil) do
    original =
      if task.url,
        do: "[##{task.number} — #{task.title}](#{task.url})",
        else: "##{task.number} — #{task.title}"

    """
    ## Desbloquear #{original}

    O agente parou esta tarefa porque falta um pré-requisito que ele não deve
    decidir sozinho. Esta tarefa resolve esse pré-requisito e libera a original.

    ### Pergunta ao dono
    #{context.question || "—"}

    ### Bloqueio registrado
    #{context.blockage || "—"}

    ## O que fazer
    - Resolva o pré-requisito acima com a menor mudança que destrave a original.
    - Registre a decisão, o caminho e a evidência (arquivo, teste, link ou print).
    - Ao terminar, comente na ##{task.number} com o que mudou e como o agente
      deve retomar; não altere o escopo da tarefa original sem necessidade.

    ## Critérios de aceite
    - [ ] O pré-requisito está resolvido e a evidência está no PR ou na issue.
    - [ ] A tarefa original ##{task.number} tem o caminho para retomar.

    Desbloqueia ##{task.number}.
    """
  end

  @doc """
  The request that opens the prerequisite issue, linked to the blocked task.

  The executor is the DeepSeek runner, so the issue mentions the bot; the
  board routes it like any other request. The key uses the exact title and
  body, so a double click returns the existing task instead of opening two.
  """
  @spec request(Repository.t(), Task.t(), String.t(), String.t()) :: map()
  def request(%Repository{} = repo, %Task{} = task, title, body) do
    %{
      title: title,
      body: body,
      key: Board.request_key(repo, "unblock", [title, body]),
      executor: "dsh",
      origin_task_id: task.id,
      blocker_for_task_id: task.id
    }
  end

  @doc "The facts the suggestion call receives. No comment body is trusted as instruction."
  @spec ai_inputs(Task.t(), Repository.t(), context()) :: map()
  def ai_inputs(%Task{} = task, %Repository{} = repo, context) do
    %{
      "task" => task.title,
      "issue" => task.number,
      "repository" => "#{repo.owner}/#{repo.name}",
      "question" => context.question || "",
      "blockage" => context.blockage || ""
    }
  end

  defp first_sentence(text) do
    text
    |> to_string()
    |> String.replace(~r/\s+/u, " ")
    |> String.split(~r/(?<=[.!?])\s+/u, parts: 2)
    |> List.first()
    |> String.trim()
    |> String.trim_trailing(".")
  end
end
