defmodule AgentBoardWeb.AdoptAgentTest do
  @moduledoc "Projects lists an agent installed outside the board and adds it with one confirmed click."
  # The profiles folder and the manager are application settings.
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Superagents}
  alias AgentBoard.Superagents.FakeManager

  setup do
    root = Path.join(System.tmp_dir!(), "adopt-panel-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "superagent"))

    File.write!(Path.join(root, "superagent/cordis.patch.yml"), """
    - id: webserver
      config:
        port: 3311
    - id: dsh-superagent
      config:
        stateDir: #{root}/state
    """)

    {:ok, _pid} = FakeManager.start()
    previous = Application.get_env(:agent_board, :superagent_manager)
    Application.put_env(:agent_board, :superagent_manager, FakeManager)
    Application.put_env(:agent_board, :dsh_profiles_dir, root)

    on_exit(fn ->
      Application.put_env(:agent_board, :dsh_profiles_dir, "/nonexistent-dsh-profiles")

      if previous,
        do: Application.put_env(:agent_board, :superagent_manager, previous),
        else: Application.delete_env(:agent_board, :superagent_manager)

      File.rm_rf!(root)
    end)

    # The board needs one repository to open.
    {:ok, repo} = Board.add_repository("fixture", "adopt-panel")
    Board.log_event(repo.id, "sync", "fixture/adopt-panel", %{"errors" => 0})
    :ok
  end

  test "the installed agent is listed, and the confirmed click makes it a project", %{conn: conn} do
    FakeManager.put_identity("superagent", %{
      repository: "fixture/installed",
      bot: "fixture-bot",
      max_workers: 2
    })

    {:ok, view, _html} = live(conn, "/?repo=fixture/adopt-panel&panel=settings&section=projects")

    refute has_element?(view, "#installed-agents")

    profile =
      Path.join(
        Application.fetch_env!(:agent_board, :dsh_profiles_dir),
        "superagent/cordis.patch.yml"
      )

    File.rename!(profile, profile <> ".later")
    view |> element(".ab-projects nav a", "Conectar o Super Agent") |> render_click()
    refute has_element?(view, "#installed-agents")
    File.rename!(profile <> ".later", profile)
    view |> element("#agent-install button", "Buscar perfis novamente") |> render_click()
    assert has_element?(view, "#installed-superagent code", "superagent")
    assert has_element?(view, "#installed-superagent", "porta 3311")

    view |> element("#adopt-superagent-trigger") |> render_click()
    assert has_element?(view, "#adopt-superagent", "A configuração dele não muda.")
    # Looking and asking changed nothing.
    assert Superagents.list() == []

    view |> element("#adopt-superagent-confirm") |> render_click()
    render_async(view, 5_000)

    assert [%{profile: "superagent", port: 3311, max_workers: 2} = superagent] =
             Superagents.list()

    assert Board.find_repository("fixture", "installed")

    html = render(view)
    assert html =~ "o board agora acompanha fixture/installed"
    assert has_element?(view, "#project-#{superagent.id}")
    refute has_element?(view, "#installed-agents")
  end

  test "a board with nothing installed outside it shows no such list", %{conn: conn} do
    Application.put_env(:agent_board, :dsh_profiles_dir, "/nonexistent-dsh-profiles")

    {:ok, view, _html} = live(conn, "/?repo=fixture/adopt-panel&panel=settings&section=projects")

    refute has_element?(view, "#installed-agents")
    assert has_element?(view, "#add-project")
  end
end
