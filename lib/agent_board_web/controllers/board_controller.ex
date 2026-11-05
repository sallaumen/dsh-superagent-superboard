defmodule AgentBoardWeb.BoardController do
  @moduledoc "The JSON API the board and the tests speak."
  use AgentBoardWeb, :controller

  import Ecto.Query, warn: false

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Repository, Task}

  # The client is injectable so the controller can be tested without GitHub.
  defp client do
    Application.get_env(:agent_board, :github_client, &AgentBoard.GitHub.client/0).()
  end

  def board(conn, params) do
    case Board.board(params["repo"]) do
      {:ok, board} -> json(conn, board)
      :error -> conn |> put_status(404) |> json(%{error: "repository not tracked"})
    end
  end

  def repos(conn, _params), do: json(conn, Board.list_repositories())

  def add_repo(conn, %{"owner" => owner, "name" => name}) do
    case Board.add_repository(owner, name) do
      {:ok, repo} ->
        conn |> put_status(201) |> json(%{id: repo.id, owner: repo.owner, name: repo.name})

      {:error, _changeset} ->
        conn |> put_status(400) |> json(%{error: "invalid"})
    end
  end

  def create_task(conn, %{"repo" => slug, "title" => title} = params) do
    with [owner, name] <- String.split(slug, "/", parts: 2),
         repo when not is_nil(repo) <-
           Repo.one(from r in Repository, where: r.owner == ^owner and r.name == ^name),
         true <- String.trim(title) != "" do
      text = String.trim(params["body"] || "") <> "\n\n@sallaumen-agent"

      case Board.create_task(repo, title, text, client()) do
        {:ok, task} ->
          conn |> put_status(201) |> json(%{id: task.id, number: task.number, url: task.url})

        {:error, changeset} ->
          conn |> put_status(400) |> json(%{error: inspect(changeset.errors)})
      end
    else
      _ -> conn |> put_status(400) |> json(%{error: "a repository and a title are required"})
    end
  end

  def act(conn, %{"id" => id, "action" => action}) do
    task = Repo.get(Task, id) |> Repo.preload(:repository)

    result =
      case {action, task} do
        {"stop", %Task{}} -> Board.stop_task(task, client())
        {"archive", %Task{}} -> Board.archive_task(task)
        {"resume", %Task{}} -> Board.resume_task(task)
        _ -> {:error, :not_found}
      end

    case result do
      {:ok, _} -> json(conn, %{ok: true})
      _ -> conn |> put_status(404) |> json(%{error: "task not found"})
    end
  end
end
