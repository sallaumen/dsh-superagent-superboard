defmodule AgentBoardWeb.BoardComponents.RepoRail do
  @moduledoc "The repository rail: one owner, the repos, their attention marks and the controls."
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.BoardComponents.Controls

  import Controls, only: [ico: 1, kbd: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  attr :view, :string, default: nil
  attr :repos, :list, default: []
  attr :repo, :any, default: nil
  attr :overview, :map, default: %{}
  attr :live, :boolean, default: false
  attr :version, :map, default: nil
  attr :busy, :boolean, default: false
  attr :voice, :map, default: nil
  attr :superagents, :list, default: []
  attr :dispatch_paused, :boolean, default: false
  attr :show_settings, :boolean, default: true
  attr :settings_panel, :boolean, default: false

  @impl true
  def render(assigns) do
    owner = owner(assigns.repo, assigns.repos)

    assigns =
      assigns
      |> assign(:owner, owner)
      |> assign(:overview, assigns.overview || %{})
      |> assign(:agent_total, Enum.sum(Enum.map(assigns.superagents, & &1.max_workers)))

    ~H"""
    <nav class="ab-rail" aria-label="Repositórios">
      <div class="ab-brand">
        <span class="ab-brand__mark" aria-hidden="true"></span>
        <span>Agent Board</span>
      </div>

      <h3 class="ab-label">{@owner}</h3>

      <button
        type="button"
        class="ab-repo ab-repo--today"
        aria-current={to_string(@view == "hoje")}
        phx-click="select"
        phx-value-view="hoje"
        title="Hoje, nos dois repositórios"
        data-initial="H"
      >
        <span class="ab-repo__name">Hoje</span>
        <span class="ab-repo__marks">
          <span :if={waiting(@overview) > 0} class="ab-repo__n ab-repo__n--you">
            <.glyph kind={:review} />{waiting(@overview)}
          </span>
        </span>
      </button>

      <button
        :for={repo <- @repos}
        type="button"
        class="ab-repo"
        aria-current={to_string(@repo && @repo.id == repo.id)}
        phx-click="select"
        phx-value-repo={"#{repo.owner}/#{repo.name}"}
        title={"#{repo.owner}/#{repo.name}"}
        data-initial={String.first(repo.name)}
      >
        <span class="ab-repo__name">{repo.name}</span>
        <span class="ab-repo__marks">
          <%= if old?(repo, @overview) do %>
            <span class="ab-repo__n ab-repo__n--unknown" title="Sem dado recente">?</span>
          <% else %>
            <span :if={running(repo, @overview) > 0} class="ab-repo__n" title="Rodando">
              <.glyph kind={:run} live={@live} />
            </span>
            <span
              :if={you(repo, @overview) > 0}
              class="ab-repo__n ab-repo__n--you"
              title={"#{you(repo, @overview)} esperando você"}
            >
              <.glyph kind={:review} />{you(repo, @overview)}
            </span>
            <span
              :if={halt(repo, @overview) > 0}
              class="ab-repo__n ab-repo__n--halt"
              title={"#{halt(repo, @overview)} bloqueados ou com CI falhando"}
            >
              <.glyph kind={:blocked} />{halt(repo, @overview)}
            </span>
          <% end %>
        </span>
      </button>

      <form id="repo-select" phx-change="select" hidden>
        <select name="repo" aria-label="Repositório">
          <option
            :for={repo <- @repos}
            value={"#{repo.owner}/#{repo.name}"}
            selected={@repo && @repo.id == repo.id}
          >
            {repo.owner}/{repo.name}
          </option>
        </select>
      </form>

      <div class="ab-rail__foot">
        <button
          id="open-superagents"
          type="button"
          class="ab-btn ab-btn--quiet ab-btn--sm"
          phx-click="show_panel"
          phx-value-panel="superagents"
          aria-label={"Superagentes: #{@agent_total} agentes em #{length(@superagents)} projetos"}
          title={"#{@agent_total} agentes em #{length(@superagents)} projetos"}
        >
          <.ico name="grip" /><span>Superagentes</span>
          <span class="ab-rail__badge" aria-hidden="true">{@agent_total}</span>
        </button>
        <button
          id="open-shortcuts"
          type="button"
          class="ab-btn ab-btn--quiet ab-btn--sm"
          phx-click="show_panel"
          phx-value-panel="shortcuts"
          data-panel-trigger
          aria-haspopup="dialog"
          aria-controls="panel-shortcuts"
          aria-label="Atalhos"
        >
          <.ico name="keys" /><span>Atalhos</span><.kbd key="?" />
        </button>
        <button
          id="open-logs"
          type="button"
          class="ab-btn ab-btn--quiet ab-btn--sm"
          phx-click="show_panel"
          phx-value-panel="logs"
          data-panel-trigger
          aria-haspopup="dialog"
          aria-controls="panel-logs"
          aria-label="Logs de avisos e erros"
        >
          <.ico name="log" /><span>Logs</span>
        </button>
        <button
          type="button"
          class="ab-btn ab-btn--quiet ab-btn--sm"
          phx-click="show_panel"
          phx-value-panel="voice"
          aria-label="Conversa por voz"
        >
          <.ico name="mic" /><span>Conversa por voz</span>
        </button>
        <.live_component
          :if={@show_settings}
          module={AgentBoardWeb.BoardComponents.SettingsMenu}
          id="board-settings"
          repo={@repo}
          version={@version}
          busy={@busy}
          voice={@voice}
          dispatch_paused={@dispatch_paused}
          settings_panel={@settings_panel}
        />
      </div>
    </nav>
    """
  end

  defp owner(nil, repos),
    do: repos |> List.wrap() |> List.first() |> then(&(&1 && &1.owner)) || ""

  defp owner(repo, _repos), do: repo.owner

  defp waiting(overview) do
    overview
    |> Map.values()
    |> Enum.map(&((&1[:you] || 0) + (&1[:halt] || 0)))
    |> Enum.sum()
  end

  defp old?(repo, overview) do
    case Map.get(overview, repo.id) do
      %{unknown: unknown} -> unknown
      _ -> false
    end
  end

  defp running(repo, overview), do: get_in(overview, [repo.id, :running]) || 0
  defp you(repo, overview), do: get_in(overview, [repo.id, :you]) || 0
  defp halt(repo, overview), do: get_in(overview, [repo.id, :halt]) || 0
end
