defmodule AgentBoardWeb.BoardController do
  @moduledoc """
  The JSON API the board and the tests speak.

  Every write goes through `AgentBoard.Actions`, by the API. A red one
  (create, stop) answers `428` with the sentence that confirms it, and runs
  only when the caller sends that sentence back as `confirm`: the caller
  states the exact consequence before it happens, and both answers are
  recorded decisions.
  """
  use AgentBoardWeb, :controller

  alias AgentBoard.{Actions, Board, Executors, GitHub, Routing}
  alias AgentBoard.Board.Task

  # The task actions the API accepts, mapped explicitly (never to_atom).
  @task_actions %{"stop" => :stop_task, "archive" => :archive_task, "resume" => :resume_task}
  @refusals [:unconfirmed, :phrase_changed]

  def board(conn, params) do
    case Board.board(params["repo"]) do
      {:ok, board} -> json(conn, board)
      :error -> conn |> put_status(404) |> json(%{error: "repository not tracked"})
    end
  end

  def repos(conn, _params), do: json(conn, Board.list_repositories())

  def add_repo(conn, %{"owner" => owner, "name" => name})
      when is_binary(owner) and is_binary(name) do
    case Actions.run(:add_repository, %{owner: owner, name: name}, api()) do
      {:ok, repo} ->
        conn |> put_status(201) |> json(%{id: repo.id, owner: repo.owner, name: repo.name})

      {:error, _changeset} ->
        conn |> put_status(400) |> json(%{error: "invalid"})
    end
  end

  def create_task(conn, %{"repo" => slug, "title" => title} = params)
      when is_binary(slug) and is_binary(title) do
    with true <- is_nil(params["body"]) or is_binary(params["body"]),
         [owner, name] <- String.split(slug, "/", parts: 2),
         {:repo, repo} when not is_nil(repo) <- {:repo, Board.find_repository(owner, name)},
         true <- String.trim(title) != "",
         true <- params["executor"] in [nil, "" | Executors.all()] do
      text = String.trim(params["body"] || "") <> "\n\n@sallaumen-agent"
      request = %{title: title, body: text, key: Board.request_key(repo, "api", [title, text])}
      # `executor` names who the task is for; without it the router suggests.
      # The API has no interface language: the reasons it stores stay Portuguese.
      request =
        Gettext.with_locale(AgentBoardWeb.Gettext, "pt_BR", fn ->
          Routing.plan(repo, request, params["executor"], "api", Routing.Signals.read_for(repo))
        end)

      action = %{repository: repo, requests: [request], client: GitHub.client()}

      case Actions.run(:create_tasks, action, api(), confirm: confirmation(params)) do
        {:ok, [{_request, {:ok, task, outcome}}]} ->
          created(conn, task, outcome)

        {:ok, [{_request, {:error, reason}}]} ->
          conn |> put_status(400) |> json(%{error: describe(reason)})

        {:error, refusal} ->
          needs_confirmation(conn, refusal)
      end
    else
      {:repo, nil} ->
        conn |> put_status(404) |> json(%{error: "repository not tracked"})

      _ ->
        conn
        |> put_status(400)
        |> json(%{
          error: "a repository and a title are required; executor is one of dsh, claude, codex"
        })
    end
  end

  def act(conn, %{"id" => id, "action" => action} = params) do
    task =
      case Board.parse_id(id) do
        nil -> nil
        task_id -> Board.task(task_id)
      end

    result =
      case {Map.get(@task_actions, action), task} do
        {name, %Task{}} when not is_nil(name) ->
          Actions.run(name, %{task: task, client: GitHub.client()}, api(),
            confirm: confirmation(params)
          )

        _ ->
          {:error, :not_found}
      end

    case result do
      {:ok, _} ->
        json(conn, %{ok: true})

      {:error, {refusal, _phrase} = gate} when refusal in @refusals ->
        needs_confirmation(conn, gate)

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "task not found"})

      {:error, reason} ->
        conn |> put_status(502) |> json(%{error: describe(reason)})
    end
  end

  # 201 for a new issue, 200 for the receipt of an earlier identical request.
  defp created(conn, task, outcome) do
    conn
    |> put_status(if outcome == :created, do: 201, else: 200)
    |> json(%{id: task.id, number: task.number, url: task.url, outcome: outcome})
  end

  # 428: nothing ran. The body carries the sentence to send back.
  defp needs_confirmation(conn, {refusal, phrase}) do
    conn
    |> put_status(428)
    |> json(%{
      error:
        if(refusal == :phrase_changed, do: "confirmation_mismatch", else: "confirmation_required"),
      confirm: phrase
    })
  end

  defp confirmation(%{"confirm" => sentence}) when is_binary(sentence), do: sentence
  defp confirmation(_params), do: nil

  defp describe(%{__exception__: true} = exception), do: Exception.message(exception)
  defp describe(%Ecto.Changeset{errors: errors}), do: inspect(errors)
  defp describe(reason), do: inspect(reason)

  defp api, do: Actions.owner(:api)
end
