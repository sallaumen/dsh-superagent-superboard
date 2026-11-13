defmodule AgentBoardWeb.BoardNavigation do
  @moduledoc "URL state for the board's in-page panels; domain actions remain in BoardLive."
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_patch: 2]

  alias AgentBoard.Board
  alias AgentBoard.Board.Task

  @panels ~w(conversation voice history composer shortcuts settings)

  # The rail shows these on a board with no repository: Settings is where the
  # first one is added, and the others do not depend on one.
  @panels_without_repo ~w(voice settings shortcuts)
  @settings_sections ~w(setup projects execution costs voice system logs)

  # Old links keep working: each key maps to the section that now holds it.
  @settings_aliases %{
    "repositories" => "projects",
    "superagents" => "projects",
    "access" => "projects",
    "dispatch" => "execution",
    "inspect" => "execution",
    "summary" => "voice",
    "appearance" => "system",
    "language" => "system",
    "version" => "system"
  }

  def path(nil), do: "/"
  def path(repo), do: "/?" <> URI.encode_query(%{"repo" => "#{repo.owner}/#{repo.name}"})

  def today_path, do: "/?view=hoje"

  def path(repo, panel, task_id \\ nil, tab \\ nil)

  def path(repo, "logs", _, _), do: settings_path(repo, "logs")

  def path(nil, panel, _task_id, _tab) when panel in @panels_without_repo, do: "/?panel=#{panel}"

  def path(repo, panel, task_id, tab) do
    query = %{"repo" => "#{repo.owner}/#{repo.name}", "panel" => panel}
    query = if task_id, do: Map.put(query, "task", task_id), else: query
    query = if tab, do: Map.put(query, "tab", tab), else: query
    "/?" <> URI.encode_query(query)
  end

  @doc """
  The history panel URL: which list it shows (ended tasks, or `"prs"` for the
  merged pull requests) and the search, so a reload or a shared link reopens it.
  """
  def history_path(repo, list \\ "tasks", query \\ "") do
    params = %{"repo" => "#{repo.owner}/#{repo.name}", "panel" => "history"}
    params = if list == "prs", do: Map.put(params, "list", "prs"), else: params
    params = if query in [nil, ""], do: params, else: Map.put(params, "q", query)
    "/?" <> URI.encode_query(params)
  end

  @doc """
  The settings panel URL, keeping the section alive across a restart. `extra`
  carries a section's own state (Costs: its page and window).
  """
  def settings_path(repo, section \\ nil, extra \\ %{}) do
    query = Map.merge(extra, %{"panel" => "settings"})
    query = if repo, do: Map.put(query, "repo", "#{repo.owner}/#{repo.name}"), else: query

    query =
      case canonical_settings_section(section) do
        nil -> query
        key -> Map.put(query, "section", key)
      end

    "/?" <> URI.encode_query(query)
  end

  @doc "The section a URL names, including the keys the old menu used."
  def canonical_settings_section(section) when section in @settings_sections, do: section
  def canonical_settings_section(section), do: Map.get(@settings_aliases, section)

  # The standalone Superagents panel (until #454) is Settings → Projects now.
  def apply_params(socket, %{"panel" => "superagents"} = params),
    do: apply_params(socket, Map.merge(params, %{"panel" => "settings", "section" => "projects"}))

  def apply_params(socket, %{"panel" => "logs"} = params),
    do: apply_params(socket, Map.merge(params, %{"panel" => "settings", "section" => "logs"}))

  # The standalone Split panel is the composer's split button now.
  def apply_params(socket, %{"panel" => "intake"} = params),
    do: apply_params(socket, Map.put(params, "panel", "composer"))

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

    section = settings_section(panel, params["section"])
    {path, pending} = project_setup(section, params["path"], socket.assigns.project_pending)

    assign(socket,
      project_pending: pending,
      panel: panel,
      conversation: nil,
      comments: [],
      inspector_tab: "conversa",
      settings_section: section,
      project_path: path,
      settings_costs: costs_params(params),
      history_list: if(params["list"] == "prs", do: "prs", else: "tasks"),
      history_query: String.slice(params["q"] || "", 0, 120),
      view: view
    )
  end

  defp project_setup("projects", "agent", pending), do: {"agent", pending}
  defp project_setup(_section, _path, _pending), do: {"github", nil}

  # Settings → Costs: the page and the window, checked by the section itself.
  defp costs_params(params) do
    %{
      source: params["source"],
      project: params["project"],
      engine: params["engine"],
      name: params["name"],
      status: params["status"],
      kind: params["kind"],
      outcome: params["outcome"],
      page: params["costs"],
      days:
        case Integer.parse(params["days"] || "") do
          {days, ""} -> days
          _ -> nil
        end
    }
  end

  defp settings_section("settings", section), do: canonical_settings_section(section)
  defp settings_section(_panel, _section), do: nil

  defp default_tab(%Task{state: "running"}), do: "atividade"
  defp default_tab(_task), do: "conversa"

  defp tab_param(tab) when tab in ~w(conversa atividade chamadas execucoes pr privado), do: tab
  defp tab_param(_tab), do: nil

  def open_task(socket, id, tab \\ nil) do
    case task(socket.assigns.repo, id) do
      nil -> socket
      task -> push_patch(socket, to: path(socket.assigns.repo, "conversation", task.id, tab))
    end
  end

  def open_panel(socket, panel) when panel in ["history", "composer"] do
    if socket.assigns.repo,
      do: push_patch(socket, to: path(socket.assigns.repo, panel)),
      else: socket
  end

  def open_panel(socket, "shortcuts"),
    do: push_patch(socket, to: path(socket.assigns.repo, "shortcuts"))

  def open_panel(socket, "superagents"), do: open_panel(socket, "settings", "projects")

  def open_panel(socket, "settings"), do: open_panel(socket, "settings", nil)

  def open_panel(socket, "voice"), do: push_patch(socket, to: path(socket.assigns.repo, "voice"))

  def open_panel(socket, "logs"), do: open_panel(socket, "settings", "logs")

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
