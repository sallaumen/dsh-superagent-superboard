defmodule AgentBoard.DependencyDelivery do
  @moduledoc """
  Reconcile board-owned blocker links with the existing Harness assignment.
  The receiver records its input and queues delivery in one transaction.
  No GitHub write, new ticket or inference from comment text.
  """
  import Ecto.Query
  require Logger
  alias AgentBoard.{Actions, Orchestrator, Repo}
  alias AgentBoard.Board.{Repository, Task}

  def reconcile(tickets, opts \\ []) do
    indexed =
      Enum.group_by(tickets, &{String.downcase(&1["repository"] || ""), &1["origin_issue"]})

    for {{repo, parent}, children} <- blocked_groups(),
        slug = String.downcase(repo.owner <> "/" <> repo.name),
        # An ambiguous origin never chooses a worker by position.
        [p] <- [Enum.filter(indexed[{slug, parent.number}] || [], &is_nil(&1["ended_at"]))],
        blocked_assignment?(p),
        {:ok, refs} <- [completed(children, indexed, slug, repo.id, p["report_at"])],
        receipt = "dependency:" <> Enum.join(Enum.sort(Enum.map(refs, & &1.ticket)), ":"),
        receipt not in (p["dependency_inputs"] || []) do
      send_input(repo, parent, p, refs, opts)
    end
  end

  defp blocked_assignment?(ticket) do
    ticket["report"] == "blocked" and ticket["assignment"] == "running" and
      is_binary(ticket["assignment_id"]) and is_struct(ticket["report_at"], DateTime) and
      not is_nil(ticket["idle_at"]) and !ticket["stopped"] and !ticket["archived"]
  end

  defp blocked_groups do
    from(c in Task,
      join: p in Task,
      on: c.blocker_for_task_id == p.id,
      join: r in Repository,
      on: r.id == p.repository_id,
      where:
        r.active and p.kind == "issue" and p.state == "blocked" and not p.stopped and
          not p.held and not p.archived,
      select: {r, p, c}
    )
    |> Repo.all()
    |> Enum.group_by(fn {r, p, _} -> {r, p} end, &elem(&1, 2))
  end

  defp completed(linked, indexed, slug, repo_id, report_at) do
    # The waiver itself is an owner message. Do not also wake for evidence
    # that already existed when that message was requested.
    cutoff = Enum.reduce(linked, report_at, &waiver_cutoff/2)
    children = Enum.reject(linked, &resolved?/1)

    refs =
      for %{
            repository_id: ^repo_id,
            kind: "issue",
            state: "done",
            github_issue_status: "completed",
            stopped: false,
            held: false,
            number: n,
            github_reopened_at: reopened
          } <- children,
          is_integer(n),
          [child] <- [indexed[{slug, n}]],
          child["ended_outcome"] in ["completed", "merged"],
          %DateTime{} = at <- [child["ended_at"]],
          is_nil(reopened) or DateTime.compare(at, reopened) != :lt,
          child["ended_outcome"] == "merged" or
            (child["report"] == "ready" and child["own_threads"] == []) do
        {at, %{number: n, ticket: child["id"]}}
      end

    if length(refs) == length(children) and
         Enum.any?(refs, fn {at, _} -> DateTime.after?(at, cutoff) end),
       do: {:ok, Enum.sort_by(Enum.map(refs, &elem(&1, 1)), & &1.number)},
       else: :waiting
  end

  defp resolved?(%Task{blocker_decision: %{"kind" => kind}}), do: kind in ["replaced", "waived"]
  defp resolved?(_), do: false

  defp waiver_cutoff(
         %Task{blocker_decision: %{"kind" => "waived", "requested_at" => raw}},
         cutoff
       ) do
    case DateTime.from_iso8601(raw) do
      {:ok, at, _} -> if DateTime.after?(at, cutoff), do: at, else: cutoff
      _ -> cutoff
    end
  end

  defp waiver_cutoff(_, cutoff), do: cutoff

  defp send_input(repo, parent, p, children, opts) do
    client = Keyword.get_lazy(opts, :client, fn -> Orchestrator.client_for(repo) end)
    slug = repo.owner <> "/" <> repo.name

    if Orchestrator.dependency_capable?(client, slug) do
      params = %{
        client: client,
        repository: repo,
        task: parent,
        ticket_id: p["id"],
        payload: %{
          repository: slug,
          number: parent.number,
          assignment: p["assignment_id"],
          children: children
        }
      }

      Actions.run(:deliver_dependencies, params, Actions.system("dependency_delivery"))
    end
  rescue
    exception ->
      Logger.warning(
        "dependency delivery for task #{parent.id} failed: #{Exception.message(exception)}"
      )
  end
end
