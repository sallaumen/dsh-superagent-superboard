defmodule AgentBoard.Board do
  @moduledoc """
  The board's read and write surface: the repositories, the tasks, the pull
  requests and the activity.
  """
  import Ecto.Query, warn: false

  alias AgentBoard.Board.{Comment, Event, PullRequest, Repository, Review, Task}
  alias AgentBoard.Repo

  @doc "Every tracked repository."
  def list_repositories, do: Repo.all(from r in Repository, order_by: r.id)

  @doc "Subscribe to a repository's live updates."
  def subscribe(repository_id) do
    Phoenix.PubSub.subscribe(AgentBoard.PubSub, "board:#{repository_id}")
  end

  @doc "Tell the subscribers of a repository that the board changed."
  def broadcast(repository_id) do
    Phoenix.PubSub.broadcast(AgentBoard.PubSub, "board:#{repository_id}", :board_updated)
  end

  @doc "Track a repository. It is a no-op if it already exists."
  def add_repository(owner, name) do
    %Repository{}
    |> Repository.changeset(%{owner: owner, name: name})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:owner, :name])
  end

  @doc "Delete a repository and everything scoped to it."
  def delete_repository(id), do: Repo.delete_all(from r in Repository, where: r.id == ^id)

  @doc "The board for a repository (the slug) or the first one."
  def board(nil), do: {:ok, board_for(first_repository())}

  def board(slug) do
    case repository_by_slug(slug) do
      nil -> :error
      repository -> {:ok, board_for(repository)}
    end
  end

  defp first_repository,
    do: Repo.one(from r in Repository, where: r.active, order_by: r.id, limit: 1)

  defp repository_by_slug(slug) do
    case String.split(slug, "/", parts: 2) do
      [owner, name] ->
        Repo.one(from r in Repository, where: r.owner == ^owner and r.name == ^name)

      _ ->
        nil
    end
  end

  defp board_for(nil) do
    %{repos: [], repo: nil, running: [], ready: [], merged: [], queued: []}
  end

  defp board_for(repository) do
    base = from t in Task, where: t.repository_id == ^repository.id

    %{
      repos: list_repositories(),
      repo: "#{repository.owner}/#{repository.name}",
      running:
        Repo.all(from t in base, where: t.state == "running", order_by: [desc: t.updated_at]),
      ready: Repo.all(from t in base, where: t.state == "ready", order_by: [desc: t.updated_at]),
      queued:
        Repo.all(from t in base, where: t.state == "queued", order_by: [desc: t.updated_at]),
      merged:
        Repo.all(
          from p in PullRequest,
            where: p.repository_id == ^repository.id and p.state == "merged",
            order_by: [desc: p.merged_at],
            limit: 30
        )
    }
  end

  @doc "Create a task by opening an issue that mentions the agent."
  def create_task(repository, title, body, client) do
    with {:ok, issue} <-
           AgentBoard.GitHub.create_issue(client, repository.owner, repository.name, title, body) do
      %Task{}
      |> Task.changeset(%{
        repository_id: repository.id,
        kind: "issue",
        number: issue["number"],
        title: title,
        body: body,
        state: "queued",
        url: issue["html_url"],
        author: "board"
      })
      |> Repo.insert(on_conflict: :nothing)
      |> tap(fn _ -> broadcast(repository.id) end)
    end
  end

  @doc "Stop a task: flag it and close the issue so the agent stops picking it up."
  def stop_task(task, client) do
    AgentBoard.GitHub.close_issue(
      client,
      task.repository.owner,
      task.repository.name,
      task.number
    )

    update_state(task, %{stopped: true, state: "stopped"})
  end

  @doc "Archive a task: remove it from the flow, keep the history."
  def archive_task(task), do: update_state(task, %{archived: true, state: "archived"})

  @doc "Resume a stopped or archived task."
  def resume_task(task),
    do: update_state(task, %{stopped: false, archived: false, state: "queued"})

  defp update_state(task, attrs) do
    result = task |> Task.changeset(attrs) |> Repo.update()
    broadcast(task.repository_id)
    result
  end

  @doc "The conversation of a task: its comments, oldest first."
  def comments(task) do
    Repo.all(from c in Comment, where: c.task_id == ^task.id, order_by: [asc: c.inserted_at])
  end

  @doc "Ask the agent: post a comment on the task's issue that mentions the agent."
  def ask(task, body, client) do
    text = String.trim(body) <> "\n\n@sallaumen-agent"

    placeholder =
      %Comment{}
      |> Comment.changeset(%{
        task_id: task.id,
        github_id: -System.unique_integer([:positive]),
        author: "you",
        body: text,
        kind: "user"
      })
      |> Repo.insert!()
      |> tap(fn _ -> broadcast(task.repository_id) end)

    case AgentBoard.GitHub.create_comment(
           client,
           task.repository.owner,
           task.repository.name,
           task.number,
           text
         ) do
      %{"id" => github_id} = comment when is_integer(github_id) ->
        placeholder
        |> Comment.changeset(%{
          github_id: github_id,
          author: get_in(comment, ["user", "login"]) || "you"
        })
        |> Repo.update()
        |> tap(fn _ -> broadcast(task.repository_id) end)

      _ ->
        Repo.delete(placeholder)
        broadcast(task.repository_id)
        {:error, :github}
    end
  rescue
    exception ->
      # The placeholder must never outlive a failed request.
      Repo.delete_all(from c in Comment, where: c.task_id == ^task.id and c.github_id < 0)
      broadcast(task.repository_id)
      {:error, exception}
  end

  @doc "Upsert a comment pulled from GitHub."
  def upsert_comment(task, comment, agent_login) do
    author = get_in(comment, ["user", "login"]) || "unknown"
    kind = if author == agent_login, do: "agent", else: "user"

    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: comment["id"],
      author: author,
      body: comment["body"] || "",
      kind: kind
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:task_id, :github_id])
  end

  @doc "The recent activity for a repository."
  def events(repository, limit \\ 20) do
    Repo.all(
      from e in Event,
        where: e.repository_id == ^repository.id,
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end

  @doc "Record an activity row."
  def log_event(repository_id, kind, subject, payload \\ %{}) do
    %Event{}
    |> Event.changeset(%{
      repository_id: repository_id,
      kind: kind,
      subject: subject,
      payload: payload
    })
    |> Repo.insert()
  end

  # The schemas are exposed so the sync and the tests can build changesets.
  def review_changeset(review, attrs), do: Review.changeset(review, attrs)
  def pull_request_changeset(pr, attrs), do: PullRequest.changeset(pr, attrs)
end
