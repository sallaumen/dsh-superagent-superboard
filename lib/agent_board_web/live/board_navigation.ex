defmodule AgentBoardWeb.BoardNavigation do
  @moduledoc "URL state for the board's in-page panels; domain actions remain in BoardLive."
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_patch: 2]

  alias AgentBoard.Board
  alias AgentBoard.Board.Task

  @panels ~w(activity intake ai conversation voice history composer shortcuts executors settings logs)

  # The rail shows these on a board with no repository: Settings is where the
  # first one is added, and the others do not depend on one.
  @panels_without_repo ~w(voice logs settings shortcuts superagents)
  @settings_sections ~w(inspect dispatch voice summary repositories superagents access appearance language version)

  def path(nil), do: "/"
  def path(repo), do: "/?" <> URI.encode_query(%{"repo" => "#{repo.owner}/#{repo.name}"})

  def today_path, do: "/?view=hoje"

  def path(repo, panel, task_id \\ nil, tab \\ nil)

  def path(nil, panel, _task_id, _tab) when panel in @panels_without_repo, do: "/?panel=#{panel}"

  def path(repo, panel, task_id, tab) do
    query = %{"repo" => "#{repo.owner}/#{repo.name}", "panel" => panel}
    query = if task_id, do: Map.put(query, "task", task_id), else: query
    query = if tab, do: Map.put(query, "tab", tab), else: query
    "/?" <> URI.encode_query(query)
  end

  @doc "The settings panel URL, keeping the section alive across a restart."
  def settings_path(repo, section \\ nil) do
    query = %{"panel" => "settings"}
    query = if repo, do: Map.put(query, "repo", "#{repo.owner}/#{repo.name}"), else: query
    query = if section in @settings_sections, do: Map.put(query, "section", section), else: query
    "/?" <> URI.encode_query(query)
  end

  # The voice panel is where a spoken question is reviewed: opening it must
  # not forget the task the owner was reading, or the ask has no target.
  def apply_params(socket, %{"panel" => "voice"}) do
    assign(socket, panel: "voice", view: nil)
  end

  def apply_params(socket, %{"panel" => "conversation", "task" => id} = params) do
    case task(socket.assigns.repo, id) do
      nil ->
        assign(socket,
          panel: nil,
          conversation: nil,
          comments: [],
          inspector_tab: "conversa",
          view: nil
        )

      task ->
        assign(socket,
          panel: "conversation",
          conversation: task,
          comments: Board.comments(task),
          inspector_tab: tab_param(params["tab"]) || default_tab(task),
          view: nil
        )
    end
  end

  def apply_params(socket, params) do
    panel = params["panel"]

    panel =
      cond do
        panel in @panels_without_repo -> panel
        socket.assigns.repo && panel in (@panels -- ["conversation", "voice"]) -> panel
        true -> nil
      end

    view = if params["view"] == "hoje", do: "hoje", else: nil

    assign(socket,
      panel: panel,
      conversation: nil,
      comments: [],
      inspector_tab: "conversa",
      settings_section: settings_section(panel, params["section"]),
      view: view
    )
  end

  defp settings_section("settings", section) when section in @settings_sections, do: section
  defp settings_section(_panel, _section), do: nil

  defp default_tab(%Task{state: "running"}), do: "atividade"
  defp default_tab(_task), do: "conversa"

  defp tab_param(tab) when tab in ~w(conversa atividade chamadas execucoes pr), do: tab
  defp tab_param(_tab), do: nil

  def open_task(socket, id, tab \\ nil) do
    case task(socket.assigns.repo, id) do
      nil -> socket
      task -> push_patch(socket, to: path(socket.assigns.repo, "conversation", task.id, tab))
    end
  end

  def open_panel(socket, panel)
      when panel in [
             "activity",
             "intake",
             "ai",
             "history",
             "composer",
             "executors"
           ] do
    if socket.assigns.repo,
      do: push_patch(socket, to: path(socket.assigns.repo, panel)),
      else: socket
  end

  def open_panel(socket, "shortcuts"),
    do: push_patch(socket, to: path(socket.assigns.repo, "shortcuts"))

  def open_panel(socket, "superagents"), do: open_panel(socket, "settings", "superagents")

  def open_panel(socket, "settings"), do: open_panel(socket, "settings", nil)

  def open_panel(socket, "voice"), do: push_patch(socket, to: path(socket.assigns.repo, "voice"))

  def open_panel(socket, "logs"), do: push_patch(socket, to: path(socket.assigns.repo, "logs"))

  def open_panel(socket, _panel), do: socket

  def open_panel(socket, "settings", section),
    do: push_patch(socket, to: settings_path(socket.assigns.repo, section))

  defp task(nil, _id), do: nil

  defp task(repo, id) do
    case Board.parse_id(id) do
      nil -> nil
      task_id -> Board.task_of(repo, task_id)
    end
  end
end
