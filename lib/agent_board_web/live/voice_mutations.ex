defmodule AgentBoardWeb.VoiceMutations do
  @moduledoc "Explicit task state requests; parsing never executes an action."

  alias AgentBoard.Board
  alias AgentBoard.Board.Task

  @stop ~r/\A(?:stop|parar|pare) (?:a |o |the )?(?:tarefa|task|issue) #?([1-9]\d*)\z/u
  @archive ~r/\A(?:archive|arquivar|arquive) (?:a |o |the )?(?:tarefa|task|issue) #?([1-9]\d*)\z/u

  @doc "Recognize only a numbered task command with an explicit action and noun."
  def parse(text) when is_binary(text) and byte_size(text) <= 500 do
    phrase =
      text
      |> String.trim()
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim_trailing(".")

    cond do
      match = Regex.run(@stop, phrase) -> intent(:stop, match)
      match = Regex.run(@archive, phrase) -> intent(:archive, match)
      true -> :not_mutation
    end
  end

  def parse(_text), do: :not_mutation

  @doc "Resolve a numbered request to a reviewable, repository-bound intent."
  def prepare(text, repo) do
    case parse(text) do
      :not_mutation -> :not_mutation
      {:ok, _request} when is_nil(repo) -> {:error, "Choose a repository first."}
      {:ok, request} -> prepare_task(request, repo)
    end
  end

  @doc "A confirmation is valid only for the same unchanged active issue."
  def current_task(%{repo_id: repo_id} = intent, %{id: repo_id} = repo) do
    case Board.find_task(repo, intent.number) do
      %Task{} = task ->
        if active?(task) and task.id == intent.task_id and task.state == intent.state and
             task.updated_at == intent.updated_at and task.title == intent.title,
           do: {:ok, task},
           else: {:error, :changed}

      nil ->
        {:error, :changed}
    end
  end

  def current_task(_intent, _repo), do: {:error, :changed}

  defp prepare_task(request, repo) do
    case Board.find_task(repo, request.number) do
      %Task{} = task ->
        if active?(task) do
          {:ok,
           Map.merge(request, %{
             repo_id: repo.id,
             repository: "#{repo.owner}/#{repo.name}",
             task_id: task.id,
             title: task.title || "unknown",
             state: task.state,
             updated_at: task.updated_at
           })}
        else
          {:error,
           "Task ##{request.number} is no longer active. Review the board before trying again."}
        end

      nil ->
        {:error, "Task ##{request.number} is not in this repository's saved data."}
    end
  end

  defp active?(%Task{kind: "issue", state: state, stopped: false, archived: false})
       when state in ~w(queued running ready blocked),
       do: true

  defp active?(_task), do: false

  defp intent(action, [_, number]) do
    case Integer.parse(number) do
      {value, ""} -> {:ok, %{action: action, number: value}}
      _ -> :not_mutation
    end
  end
end
