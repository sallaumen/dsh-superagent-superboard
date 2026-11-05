defmodule AgentBoardWeb.BoardNavigation do
  @moduledoc "URL state for the board's in-page panels; domain actions remain in BoardLive."
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_patch: 2]

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @panels ~w(activity intake ai create conversation voice)

  def path(nil), do: "/"
  def path(repo), do: "/?" <> URI.encode_query(%{"repo" => "#{repo.owner}/#{repo.name}"})

  def path(repo, panel, task_id \\ nil)

  def path(nil, "voice", _task_id), do: "/?panel=voice"

  def path(repo, panel, task_id) do
    query = %{"repo" => "#{repo.owner}/#{repo.name}", "panel" => panel}
    query = if task_id, do: Map.put(query, "task", task_id), else: query
    "/?" <> URI.encode_query(query)
  end

  def apply_params(socket, %{"panel" => "conversation", "task" => id}) do
    case task(socket.assigns.repo, id) do
      nil ->
        assign(socket, panel: nil, conversation: nil, comments: [])

      task ->
        assign(socket, panel: "conversation", conversation: task, comments: Board.comments(task))
    end
  end

  def apply_params(socket, params) do
    panel = params["panel"]

    panel =
      cond do
        panel == "voice" -> panel
        socket.assigns.repo && panel in (@panels -- ["conversation", "voice"]) -> panel
        true -> nil
      end

    assign(socket, panel: panel, conversation: nil, comments: [])
  end

  def open_task(socket, id) do
    case task(socket.assigns.repo, id) do
      nil -> socket
      task -> push_patch(socket, to: path(socket.assigns.repo, "conversation", task.id))
    end
  end

  def open_panel(socket, panel) when panel in ["activity", "intake", "ai", "create"] do
    if socket.assigns.repo,
      do: push_patch(socket, to: path(socket.assigns.repo, panel)),
      else: socket
  end

  def open_panel(socket, "voice"), do: push_patch(socket, to: path(socket.assigns.repo, "voice"))

  def open_panel(socket, _panel), do: socket

  defp task(nil, _id), do: nil

  defp task(repo, id) do
    with {number, ""} <- Integer.parse(to_string(id)),
         %Task{repository_id: repo_id} = task <- Repo.get(Task, number),
         true <- repo_id == repo.id do
      task
    else
      _ -> nil
    end
  end
end
