defmodule AgentBoardWeb.SettingsSectionTest do
  @moduledoc """
  The settings section lives in the URL, so an update restart returns to it.
  The ten keys of the old menu keep working and open the section that holds
  their content now.
  """
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Superagents}
  alias AgentBoardWeb.BoardNavigation

  @aliases [
    {"repositories", "projects", "Projetos", "settings-projects-title"},
    {"superagents", "projects", "Projetos", "settings-projects-title"},
    {"access", "projects", "Projetos", "settings-projects-title"},
    {"dispatch", "execution", "Execução", "settings-execution-title"},
    {"inspect", "execution", "Execução", "settings-execution-title"},
    {"summary", "voice", "Voz e resumo", "settings-voice-title"},
    {"appearance", "system", "Sistema", "settings-system-title"},
    {"language", "system", "Sistema", "settings-system-title"},
    {"version", "system", "Sistema", "settings-system-title"}
  ]

  test "settings_path writes the current section and keeps the repository" do
    {:ok, repo} = Board.add_repository("fixture", "sections")

    assert BoardNavigation.settings_path(repo, "system") ==
             "/?panel=settings&repo=fixture%2Fsections&section=system"

    assert BoardNavigation.settings_path(repo, nil) ==
             "/?panel=settings&repo=fixture%2Fsections"

    assert BoardNavigation.settings_path(repo, "unknown") ==
             "/?panel=settings&repo=fixture%2Fsections"
  end

  test "settings_path maps every old section key to its new one" do
    {:ok, repo} = Board.add_repository("fixture", "old-sections")

    for {old, new, _label, _title} <- @aliases do
      assert BoardNavigation.settings_path(repo, old) ==
               "/?panel=settings&repo=fixture%2Fold-sections&section=#{new}"
    end
  end

  test "the URL section opens the right pane and survives a nav change", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "sections-live")

    {:ok, view, _html} =
      live(conn, ~p"/?repo=fixture/sections-live&panel=settings&section=system")

    assert has_element?(view, "section[aria-labelledby=settings-system-title]")
    refute has_element?(view, "section[aria-labelledby=settings-system-title][hidden]")
    assert has_element?(view, "section[aria-labelledby=settings-execution-title][hidden]")

    view
    |> element(".settings-nav button[phx-value-section=execution]")
    |> render_click()

    assert_patch(view, "/?panel=settings&repo=fixture%2Fsections-live&section=execution")
    refute has_element?(view, "section[aria-labelledby=settings-execution-title][hidden]")
  end

  test "every old section key opens the section that holds its content", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "aliases")

    for {old, _new, label, title} <- @aliases do
      {:ok, view, _html} =
        live(conn, "/?repo=fixture/aliases&panel=settings&section=#{old}")

      assert has_element?(view, ".settings-nav__item.is-current", label),
             "old key #{old} should open #{label}"

      assert has_element?(view, "section[aria-labelledby=#{title}]"),
             "old key #{old} should render #{title}"
    end
  end

  # The standalone Superagents panel (until #454) had its own URL.
  test "the old Superagents panel URL opens Projects", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?panel=superagents")

    assert has_element?(view, "[data-panel=settings]")
    assert has_element?(view, ".settings-nav__item.is-current", "Projetos")

    {:ok, _repo} = Board.add_repository("fixture", "old-panel")
    {:ok, view, _html} = live(conn, "/?repo=fixture/old-panel&panel=superagents")

    assert has_element?(view, "[data-panel=settings]")
    assert has_element?(view, ".settings-nav__item.is-current", "Projetos")
    refute has_element?(view, "section[aria-labelledby=settings-projects-title][hidden]")
  end

  test "an old show_panel section link still opens the new section", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "old-link")

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/old-link")

    render_hook(view, "show_panel", %{"panel" => "settings", "section" => "version"})

    assert_patch(view, "/?panel=settings&repo=fixture%2Fold-link&section=system")
    assert has_element?(view, ".settings-nav__item.is-current", "Sistema")
  end

  test "a project with an error marks Projects", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "error-mark")

    {:ok, _superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-error-mark",
        port: 3499,
        state_dir: "/tmp/superagent-error-mark",
        observed_state: "error",
        last_error: "github: sem acesso"
      })

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/error-mark&panel=settings")

    assert has_element?(view, ".settings-nav__mark--halt", "1")
    assert has_element?(view, ".settings-nav__mark--halt", "1 projeto com erro")
  end

  test "Execution opens on a board with no repository and hides the repo-only Inspect", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/?panel=settings&section=execution")

    assert has_element?(view, "#toggle-dispatch")
    assert has_element?(view, "#execution-settings-form")
    refute has_element?(view, "#open-activity")
  end

  test "the navigation footer names the running commit and links to System", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "footer")

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/footer&panel=settings")

    assert has_element?(view, ".settings-nav__foot", "Rodando")
    assert has_element?(view, ".settings-nav__foot-link", "Ver atualização")

    view |> element(".settings-nav__foot-link") |> render_click()

    assert_patch(view, "/?panel=settings&repo=fixture%2Ffooter&section=system")
    assert has_element?(view, ".settings-nav__item.is-current", "Sistema")
  end

  test "AI and setup lists what each agent has installed, and unread is not zero", %{conn: conn} do
    home = Path.join(System.tmp_dir!(), "setup-tools-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(home, ".claude/skills/review"))

    File.write!(
      Path.join(home, ".claude/skills/review/SKILL.md"),
      "---\ndescription: Reviews.\n---\n"
    )

    File.ln_s!(Path.join(home, "gone"), Path.join(home, ".claude/skills/broken"))
    Application.put_env(:agent_board, :agent_tools_home, home)

    on_exit(fn ->
      Application.put_env(:agent_board, :agent_tools_home, "/nonexistent-agent-tools-home")
      File.rm_rf!(home)
    end)

    {:ok, view, _html} = live(conn, ~p"/?panel=settings&section=setup")

    assert has_element?(view, "#setup-tools-claude_code summary", "2 skills · 1 com defeito")
    assert has_element?(view, "#setup-tools-claude_code", "Reviews.")
    assert has_element?(view, "#setup-tools-claude_code .setup__tool-broken")

    assert has_element?(
             view,
             "#setup-tools-dsh summary",
             "0 skills · ? servidores MCP · ? plugins"
           )

    assert has_element?(view, "#setup-tools-codex", "Nenhum instalado.")
  end
end
