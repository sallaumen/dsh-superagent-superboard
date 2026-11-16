defmodule AgentBoard.BlockerDecisions do
  @moduledoc "Owner decisions about a prerequisite that GitHub explicitly closed without completing."
  import Ecto.Query
  alias AgentBoard.{Board, GitHub, Repo}
  alias AgentBoard.Board.Task

  def cancelled?(%Task{github_issue_status: status}), do: status in ["not_planned", "duplicate"]

  def eligible?(parent, child) do
    parent.state == "blocked" and not parent.stopped and not parent.archived and
      not parent.held and child.blocker_for_task_id == parent.id and
      child.repository_id == parent.repository_id and cancelled?(child) and
      is_nil(child.blocker_decision)
  end

  def replacement?(parent, old, candidate) do
    candidate.id != old.id and candidate.blocker_for_task_id == parent.id and
      candidate.repository_id == parent.repository_id and open_child?(candidate)
  end

  defp open_child?(
         %Task{kind: "issue", number: n, stopped: false, archived: false, blocker_decision: nil} =
           child
       )
       when is_integer(n),
       do: child.state not in ~w(done closed stopped archived) and not cancelled?(child)

  defp open_child?(_), do: false

  def resolve(%{task: parent, child: old, choice: choice, reason: raw} = params, post)
      when choice in ["replace", "waive"] and is_binary(raw) do
    reason = String.trim(raw)

    with true <- String.length(reason) in 1..2000,
         {:ok, {task, child, decision}} <-
           Repo.transaction(fn -> reserve(parent, old, choice, params, reason) end) do
      Board.broadcast(task.repository_id)
      notify_owner_decision(task, child, decision, post)
    else
      false -> {:error, :invalid_reason}
      error -> error
    end
  end

  defp reserve(parent, old, choice, params, reason) do
    task = lock(parent.id)
    child = lock(old.id)
    unless task && child && eligible?(task, child), do: Repo.rollback(:stale_blocker)
    decision = decision(task, child, choice, params, reason)
    save(child, decision)
    {task, child, decision}
  end

  defp lock(id), do: Repo.one(from t in Task, where: t.id == ^id, lock: "FOR UPDATE")

  defp decision(_parent, _child, "waive", _params, reason),
    do: %{
      "kind" => "waiver_pending",
      "reason" => reason,
      "requested_at" => DateTime.to_iso8601(DateTime.utc_now())
    }

  defp decision(parent, old, "replace", params, reason) do
    candidate = if is_integer(params[:replacement_id]), do: lock(params.replacement_id)

    unless candidate && replacement?(parent, old, candidate),
      do: Repo.rollback(:invalid_replacement)

    %{"kind" => "replaced", "replacement" => candidate.number, "reason" => reason}
  end

  defp save(child, decision) do
    child |> Ecto.Changeset.change(blocker_decision: decision) |> Repo.update!()
  end

  defp notify_owner_decision(_parent, _child, %{"kind" => "replaced"}, _client),
    do: {:ok, :replaced}

  defp notify_owner_decision(parent, child, reservation, post) do
    body = """
    #{Gettext.dgettext(AgentBoardWeb.Gettext, "default", "Owner waiver for prerequisite #%{child} of #%{parent}.", child: child.number, parent: parent.number)}

    #{child.title}

    #{reservation["reason"]}

    #{Gettext.dgettext(AgentBoardWeb.Gettext, "default", "The evidence was not delivered. Waive only this requirement; any other unmet requirements remain blocking. Record the decision on the original ticket.")}
    """

    # Claim before the network call. An ambiguous write is never automatically repeated.
    case post.(parent, body) do
      {:ok, comment} ->
        save(child, Map.merge(reservation, %{"kind" => "waived", "comment" => comment.github_id}))
        Board.broadcast(parent.repository_id)
        {:ok, :waived}

      {:error, %GitHub.RateLimited{}} ->
        release_refused(child, parent)

      {:error, %GitHub.HTTPError{status: code}} when code in [400, 401, 403, 404, 422] ->
        release_refused(child, parent)

      _ ->
        {:error, :waiver_unconfirmed}
    end
  end

  # GitHub explicitly refused this POST, so the owner may safely try again.
  # Lose no ambiguous receipt: a timeout still retains the durable reservation.
  defp release_refused(child, parent) do
    save(Repo.reload!(child), nil)
    Board.broadcast(parent.repository_id)
    {:error, :waiver_refused}
  end
end
