defmodule AgentBoardWeb.SuperagentsPanelTest do
  @moduledoc "The superagents panel: project status, controls and provisioning."
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

  test "renders one title with project status, details and error", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "panel")
    superagent = superagent!(repo, %{observed_state: "error", last_error: "github: sem acesso"})
    {:ok, _} = Superagents.observe(superagent, %{state: "error", detail: "github: sem acesso"})

    {:ok, view, html} = live(conn, "/?repo=fixture/panel&panel=superagents")

    assert html =~ "Superagentes DeepSeek"
    assert html =~ "fixture/panel"
    assert html =~ "superagent-panel"
    assert html =~ "erro"
    assert html =~ "github: sem acesso"
    assert has_element?(view, "#panel-superagents h2#panel-title-superagents")
    refute has_element?(view, "#superagents-panel h2")
    assert has_element?(view, "#superagents-panel .ab-superagent-table__details")
  end

  test "summarizes a long GitHub limit error and keeps its diagnostic", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "rate-limited-panel")
    superagent = superagent!(repo, %{observed_state: "error"})

    detail =
      "github: 3 consecutive failed polls; last: API rate limit exceeded for user ID 123. " <>
        String.duplicate("Request details. ", 12)

    {:ok, _} = Superagents.observe(superagent, %{state: "error", detail: detail})

    {:ok, view, _html} = live(conn, "/?repo=fixture/rate-limited-panel&panel=superagents")

    assert has_element?(view, ".ab-superagents__errors", "O GitHub atingiu o limite de consultas")
    assert has_element?(view, ".ab-superagents__errors details", "Detalhes técnicos")
    assert has_element?(view, ".ab-superagents__errors code", "rate limit exceeded")
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

    {:ok, view, html} = live(conn, "/?repo=fixture/controls&panel=superagents")
    assert html =~ "Pausar"
    assert html =~ "Parar"

    view
    |> element("#superagents-panel button[phx-value-action='pause']")
    |> render_click()

    Process.sleep(100)
    _ = render(view)
    assert Repo.get!(Superagent, superagent.id).desired_state == "paused"

    view
    |> element("#superagents-panel button[phx-value-delta='1']")
    |> render_click()

    Process.sleep(100)
    _ = render(view)
    assert Repo.get!(Superagent, superagent.id).max_workers == superagent.max_workers + 1
  end

  test "the add-project form previews and confirms a new project", %{conn: conn} do
    {:ok, source_repo} = Board.add_repository("fixture", "source-panel")
    {:ok, target} = Board.add_repository("fixture", "target-panel")

    {:ok, source} =
      Superagents.create(%{
        repository_id: source_repo.id,
        profile: "superagent-source-panel",
        port: 3190,
        state_dir: "/tmp/source-panel"
      })

    previous = Application.get_env(:agent_board, :superagent_provisioner)
    Application.put_env(:agent_board, :superagent_provisioner, FakeProvisioner)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :superagent_provisioner, previous),
        else: Application.delete_env(:agent_board, :superagent_provisioner)
    end)

    {:ok, view, _html} = live(conn, "/?repo=fixture/target-panel&panel=superagents")

    view
    |> form(".ab-superagent-add__form", %{
      "repository_id" => target.id,
      "source_id" => source.id,
      "path" => "/tmp/target-checkout",
      "workers" => "2"
    })
    |> render_submit()

    assert has_element?(view, ".ab-superagent-add__preview", "Provisionar o DeepSeek")

    view |> element(".ab-superagent-add__preview button", "Adicionar e iniciar") |> render_click()
    Process.sleep(150)
    _ = render(view)

    assert superagent = Superagents.get_by_repository(target)
    assert superagent.max_workers == 2
  end

  test "each project keeps its own agent pool and the panel sums the total", %{conn: conn} do
    {:ok, one} = Board.add_repository("fixture", "pool-one")
    {:ok, two} = Board.add_repository("fixture", "pool-two")
    first = superagent!(one, %{max_workers: 2})
    second = superagent!(two, %{max_workers: 4})

    {:ok, view, _html} = live(conn, "/?repo=fixture/pool-one&panel=superagents")

    assert has_element?(
             view,
             "#superagents-panel .ab-superagents__summary",
             "6 agentes configurados"
           )

    assert has_element?(view, "#superagent-#{first.id} .ab-superagent__workers", "2")
    assert has_element?(view, "#superagent-#{second.id} .ab-superagent__workers", "4")
    refute has_element?(view, "#superagents-panel a[href='#superagent-add']")

    assert has_element?(
             view,
             "#superagents-panel .ab-superagents__complete",
             "Todos os repositórios"
           )

    assert Repo.get!(Superagent, first.id).max_workers == 2
    assert Repo.get!(Superagent, second.id).max_workers == 4
  end

  test "an empty board says no superagent is registered", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "empty-panel")
    {:ok, _view, html} = live(conn, "/?repo=fixture/empty-panel&panel=superagents")

    assert html =~ "Nenhum superagente registrado"
  end

  test "a control for a superagent removed elsewhere says so and keeps the socket", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "gone")
    superagent = superagent!(repo, %{observed_state: "ready"})
    {:ok, view, _html} = live(conn, "/?repo=fixture/gone&panel=superagents")

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
