defmodule AgentBoardWeb.SuperagentsPanelTest do
  @moduledoc "Settings → Projects: project rows, controls and provisioning."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo, Superagents}
  alias AgentBoard.Superagents.{FakeManager, FakeProvisioner, Superagent}

  defp superagent!(repo, attrs) do
    {:ok, superagent} =
      Superagents.create(
        Map.merge(
          %{
            repository_id: repo.id,
            profile: "superagent-#{repo.name}",
            port: 3190 + rem(repo.id, 1000),
            state_dir: "/tmp/superagent-#{repo.name}"
          },
          attrs
        )
      )

    superagent
  end

  test "renders the project row with state, details and the error under it", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "panel")
    superagent = superagent!(repo, %{observed_state: "error", last_error: "github: sem acesso"})
    {:ok, _} = Superagents.observe(superagent, %{state: "error", detail: "github: sem acesso"})

    {:ok, view, html} = live(conn, "/?repo=fixture/panel&panel=settings&section=projects")

    assert html =~ "fixture/panel"
    assert html =~ "superagent-panel"
    assert html =~ "Não sobe"
    assert has_element?(view, "#settings-projects-title")

    assert has_element?(
             view,
             "#project-#{superagent.id} .ab-project__error",
             "github: sem acesso"
           )

    view
    |> element("#project-#{superagent.id} button[phx-click=toggle_project]")
    |> render_click()

    assert has_element?(
             view,
             "#project-#{superagent.id}-details .ab-project__fold",
             "Pasta de estado"
           )
  end

  test "summarizes a long GitHub limit error and keeps its diagnostic", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "rate-limited-panel")
    superagent = superagent!(repo, %{observed_state: "error"})

    detail =
      "github: 3 consecutive failed polls; last: API rate limit exceeded for user ID 123. " <>
        String.duplicate("Request details. ", 12)

    {:ok, _} = Superagents.observe(superagent, %{state: "error", detail: detail})

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/rate-limited-panel&panel=settings&section=projects")

    assert has_element?(
             view,
             "#project-#{superagent.id} .ab-project__error",
             "O GitHub atingiu o limite de consultas"
           )

    assert has_element?(
             view,
             "#project-#{superagent.id} .ab-project__error details",
             "Detalhes técnicos"
           )

    assert has_element?(
             view,
             "#project-#{superagent.id} .ab-project__error code",
             "rate limit exceeded"
           )
  end

  test "a ready project can be paused and scaled", %{conn: conn} do
    {:ok, pid} = FakeManager.start()
    previous = Application.get_env(:agent_board, :superagent_manager)
    Application.put_env(:agent_board, :superagent_manager, FakeManager)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :superagent_manager, previous),
        else: Application.delete_env(:agent_board, :superagent_manager)

      if Process.alive?(pid), do: Agent.stop(pid)
    end)

    {:ok, repo} = Board.add_repository("fixture", "controls")
    superagent = superagent!(repo, %{observed_state: "ready"})
    {:ok, _} = Superagents.observe(superagent, %{state: "ready"})
    FakeManager.put(superagent.id, %{state: "ready"})

    {:ok, view, html} = live(conn, "/?repo=fixture/controls&panel=settings&section=projects")
    assert html =~ "Pausar"

    view
    |> element("#project-#{superagent.id} button[phx-value-action='pause']")
    |> render_click()

    Process.sleep(100)
    _ = render(view)
    assert Repo.get!(Superagent, superagent.id).desired_state == "paused"

    view
    |> element("#project-#{superagent.id} button[phx-value-delta='1']")
    |> render_click()

    Process.sleep(100)
    _ = render(view)
    assert Repo.get!(Superagent, superagent.id).max_workers == superagent.max_workers + 1
  end

  test "the add-project form previews the sentence, the workers and confirms", %{conn: conn} do
    {:ok, _source_repo} = Board.add_repository("fixture", "source-panel")
    {:ok, target} = Board.add_repository("fixture", "target-panel")

    profiles =
      Path.join(System.tmp_dir!(), "dsh-profiles-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(profiles, "superagent"))

    File.write!(
      Path.join([profiles, "superagent", "cordis.patch.yml"]),
      "webserver:\n  port: 3082\n"
    )

    previous = Application.get_env(:agent_board, :superagent_provisioner)
    previous_profiles = Application.get_env(:agent_board, :dsh_profiles_dir)
    Application.put_env(:agent_board, :superagent_provisioner, FakeProvisioner)
    Application.put_env(:agent_board, :dsh_profiles_dir, profiles)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :superagent_provisioner, previous),
        else: Application.delete_env(:agent_board, :superagent_provisioner)

      if previous_profiles,
        do: Application.put_env(:agent_board, :dsh_profiles_dir, previous_profiles),
        else: Application.delete_env(:agent_board, :dsh_profiles_dir)

      File.rm_rf!(profiles)
    end)

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/target-panel&panel=settings&section=projects")

    view
    |> form("#track-repo", %{
      "owner" => target.owner,
      "name" => target.name,
      "path" => "/tmp/target-checkout",
      "create_agent" => "true",
      "workers" => "2"
    })
    |> render_submit()

    assert has_element?(view, "#add-project-confirm", "Provisionar o DeepSeek")
    assert has_element?(view, "#add-project-confirm", "2")

    view |> element("#add-project-confirm button", "Criar superagente") |> render_click()
    Process.sleep(150)
    _ = render(view)

    assert superagent = Superagents.get_by_repository(target)
    assert superagent.max_workers == 2
  end

  test "each project keeps its own agent pool and the list sums the total", %{conn: conn} do
    {:ok, one} = Board.add_repository("fixture", "pool-one")
    {:ok, two} = Board.add_repository("fixture", "pool-two")
    first = superagent!(one, %{max_workers: 2})
    second = superagent!(two, %{max_workers: 4})

    {:ok, view, _html} = live(conn, "/?repo=fixture/pool-one&panel=settings&section=projects")

    assert has_element?(view, ".ab-projects__summary", "6 agentes")
    assert has_element?(view, "#project-#{first.id} .ab-project__agent-count", "2")
    assert has_element?(view, "#project-#{second.id} .ab-project__agent-count", "4")

    assert Repo.get!(Superagent, first.id).max_workers == 2
    assert Repo.get!(Superagent, second.id).max_workers == 4
  end

  test "an empty board says no project is registered", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "empty-panel")

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/empty-panel&panel=settings&section=projects")

    assert has_element?(view, ".ab-projects__empty", "Nenhum projeto ainda")
  end

  test "a control for a superagent removed elsewhere says so and keeps the socket", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "gone")
    superagent = superagent!(repo, %{observed_state: "ready"})
    {:ok, view, _html} = live(conn, "/?repo=fixture/gone&panel=settings&section=projects")

    Repo.delete!(superagent)

    assert render_hook(view, "superagent_command", %{
             "id" => to_string(superagent.id),
             "action" => "pause"
           }) =~ "não está mais no board"

    assert render_hook(view, "superagent_scale", %{
             "id" => to_string(superagent.id),
             "delta" => "1"
           }) =~ "não está mais no board"

    assert Process.alive?(view.pid)
  end
end
