defmodule AgentBoardWeb.SuperagentsPanelTest do
  @moduledoc "Settings → Projects: project rows, controls and provisioning."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo, Superagents}
  alias AgentBoard.Superagents.{FakeManager, FakeProvisioner, Leftovers, Policy, Superagent}

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

    refute has_element?(
             view,
             "#project-#{superagent.id} a[href='http://127.0.0.1:#{superagent.port}/']"
           )

    refute has_element?(view, "#project-setup-options[open]")

    # The button posts to the board, with the session's token; no address is in the page.
    form = "#project-#{superagent.id}-panel-form"

    assert has_element?(
             view,
             form <> "[method=post][action='/superagents/#{superagent.id}/panel']"
           )

    assert has_element?(view, form <> " input[name=_csrf_token]")
    refute render(view) =~ "token="

    assert has_element?(
             view,
             "#project-#{superagent.id} .ab-project__error",
             "github: sem acesso"
           )

    view
    |> element("#project-#{superagent.id} button[phx-click=toggle_project]")
    |> render_click()

    controls = "#project-#{superagent.id}-details"
    assert has_element?(view, controls <> " [phx-value-section=merge][aria-pressed=true]")
    assert has_element?(view, "#project-#{superagent.id}-view-maintenance[hidden]")
    view |> element(controls <> " [phx-value-section=maintenance]") |> render_click()
    assert has_element?(view, "#project-#{superagent.id}-view-merge[hidden]")
    assert has_element?(view, "#project-#{superagent.id}-view-maintenance:not([hidden])")

    assert has_element?(
             view,
             "#project-#{superagent.id}-details .ab-project__fold",
             "Pasta de estado"
           )
  end

  # The policy panel reads the agent through the configured manager.
  defp fake_manager do
    {:ok, _pid} = FakeManager.start()
    previous = Application.get_env(:agent_board, :superagent_manager)
    Application.put_env(:agent_board, :superagent_manager, FakeManager)
    Policy.forget()

    on_exit(fn ->
      Policy.forget()

      if previous,
        do: Application.put_env(:agent_board, :superagent_manager, previous),
        else: Application.delete_env(:agent_board, :superagent_manager)
    end)
  end

  test "an agent with other instructions is in the bell, and one click applies the policy",
       %{conn: conn} do
    fake_manager()

    {:ok, repo} = Board.add_repository("fixture", "policy-panel")
    Board.log_event(repo.id, "sync", "fixture/policy-panel", %{"errors" => 0})
    superagent = superagent!(repo, %{})

    own = "Every UI change shows a before and an after."
    stale = "An older wording of a rule."

    FakeManager.put_prompts(superagent.id, %{
      revision: 7,
      config: Map.put(Policy.base(), "delivery", stale <> "\n" <> own)
    })

    :ok = Policy.refresh_all(FakeManager)

    {:ok, view, _html} = live(conn, "/?repo=fixture/policy-panel&panel=settings&section=projects")

    assert has_element?(
             view,
             "#attention-agent-policy",
             "As instruções de 1 agente diferem da política do board"
           )

    view
    |> element("#project-#{superagent.id} button[phx-click=toggle_project]")
    |> render_click()

    render_async(view, 5_000)
    panel = "#project-#{superagent.id}-policy"

    assert has_element?(view, panel, "Diferentes da política do board.")
    assert has_element?(view, panel, "Requisitos de entrega")
    assert has_element?(view, panel <> " input[name='keep[]']")
    assert has_element?(view, panel, own)
    # Nothing was written by looking.
    assert {:ok, %{revision: 7}} = FakeManager.prompts(superagent)

    {:ok, comparison} = Policy.compare(superagent, FakeManager)
    delivery = Enum.find(comparison.sections, &(&1.name == "delivery"))
    keep = for line <- delivery.own, line.text == own, do: line.id

    view
    |> element("#project-#{superagent.id}-policy-form")
    |> render_submit(%{"keep" => keep})

    render_async(view, 5_000)

    assert {:ok, %{revision: 8, config: config}} = FakeManager.prompts(superagent)
    assert config["delivery"] == Policy.base()["delivery"] <> "\n" <> own
    assert has_element?(view, panel, "Em dia com a política do board.")
    assert has_element?(view, panel, "Regras deste projeto")
    assert Policy.differing() == []

    # The click is a recorded action of the registry, like every other write.
    assert %{outcome: "ok", via: "ui"} =
             Repo.get_by!(AgentBoard.Actions.Decision, action: "apply_agent_policy")
  end

  test "an agent that does not answer says so, with no button to apply", %{conn: conn} do
    fake_manager()
    {:ok, repo} = Board.add_repository("fixture", "policy-silent")
    superagent = superagent!(repo, %{})
    FakeManager.put_prompts(superagent.id, {:error, :econnrefused})

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/policy-silent&panel=settings&section=projects")

    view
    |> element("#project-#{superagent.id} button[phx-click=toggle_project]")
    |> render_click()

    render_async(view, 5_000)

    assert has_element?(view, "#project-#{superagent.id}-policy", "O agente não respondeu")
    refute has_element?(view, "#project-#{superagent.id}-policy-form")
  end

  test "a project's ended folders are measured, kept for the chosen days and removed by the red button",
       %{conn: conn} do
    fake_manager()
    root = Path.join(System.tmp_dir!(), "leftovers-panel-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = AgentBoard.LeftoversFixture.build!(root)

    {:ok, repo} = Board.add_repository("fixture", "leftovers-panel")
    Board.log_event(repo.id, "sync", "fixture/leftovers-panel", %{"errors" => 0})
    superagent = superagent!(repo, %{state_dir: fixture.state})

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/leftovers-panel&panel=settings&section=projects")

    view
    |> element("#project-#{superagent.id} button[phx-click=toggle_project]")
    |> render_click()

    render_async(view, 10_000)
    panel = "#project-#{superagent.id}-leftovers"

    assert has_element?(view, panel, "2 pastas")
    assert has_element?(view, panel, "Mais 1 fica")
    assert has_element?(view, panel, "há mais de 30 dias")
    assert has_element?(view, panel, "Hoje 1 passa desse prazo.")
    assert has_element?(view, panel <> " option[value='30'][selected]")

    view
    |> element("#project-#{superagent.id}-leftovers-form")
    |> render_change(%{"days" => "never"})

    assert Leftovers.days(superagent) == :never
    assert has_element?(view, panel, "O board não remove nada sozinho")

    # Looking and choosing removed nothing.
    assert Enum.all?(Map.values(fixture.dirs), &File.dir?/1)

    button = "#project-clean-leftovers-#{superagent.id}"
    view |> element(button <> "-trigger") |> render_click()
    assert has_element?(view, button, "As pastas não voltam.")
    view |> element(button <> "-confirm") |> render_click()
    # The removal, then the panel measuring again.
    render_async(view, 10_000)
    render_async(view, 10_000)

    # The button leaves with the last folder; the panel says what happened.
    assert has_element?(view, "#panel-settings-info", "2 pastas removidas")
    refute has_element?(view, button)
    refute File.dir?(fixture.dirs["old"])
    refute File.dir?(fixture.dirs["recent"])
    assert File.dir?(fixture.dirs["dirty"])
    assert File.dir?(fixture.dirs["open"])

    assert has_element?(view, panel, "Nenhuma pasta de ticket encerrado no disco.")

    assert %{outcome: "ok", via: "ui", decision: "confirmed"} =
             Repo.get_by!(AgentBoard.Actions.Decision, action: "clean_agent_leftovers")
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

  test "the card stops at the agent's limit and sends nothing above it", %{conn: conn} do
    {:ok, pid} = FakeManager.start()
    previous = Application.get_env(:agent_board, :superagent_manager)
    Application.put_env(:agent_board, :superagent_manager, FakeManager)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :superagent_manager, previous),
        else: Application.delete_env(:agent_board, :superagent_manager)

      if Process.alive?(pid), do: Agent.stop(pid)
    end)

    {:ok, repo} = Board.add_repository("fixture", "ceiling")
    superagent = superagent!(repo, %{max_workers: 16})

    {:ok, view, _html} = live(conn, "/?repo=fixture/ceiling&panel=settings&section=projects")

    assert has_element?(
             view,
             "#project-#{superagent.id} button[phx-value-delta='1'][disabled]"
           )

    render_hook(view, "superagent_scale", %{"id" => to_string(superagent.id), "delta" => "1"})
    render_async(view, 2_000)

    assert Repo.get!(Superagent, superagent.id).max_workers == 16
  end

  test "the add-project form previews the sentence, the workers and confirms", %{conn: conn} do
    {:ok, _source_repo} = Board.add_repository("fixture", "source-panel")
    {:ok, target} = Board.add_repository("fixture", "target-panel")

    profiles =
      Path.join(System.tmp_dir!(), "dsh-profiles-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(profiles, "superagent"))

    File.write!(
      Path.join([profiles, "superagent", "cordis.patch.yml"]),
      "webserver:\n  port: 3082\n- id: dsh-superagent\n"
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
      live(conn, "/?repo=fixture/target-panel&panel=settings&section=projects&path=agent")

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

  test "a board with no repository says no project is registered", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?panel=settings&section=projects")

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

  test "a failed provisioning offers a retry instead of starting", %{conn: conn} do
    {:ok, pid} = FakeManager.start()
    previous = Application.get_env(:agent_board, :superagent_provisioner)
    Application.put_env(:agent_board, :superagent_provisioner, FakeProvisioner)

    root = Path.join(System.tmp_dir!(), "retry-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "superagent"))
    File.write!(Path.join([root, "superagent", "cordis.patch.yml"]), "port: 3489\n")
    Application.put_env(:agent_board, :dsh_profiles_dir, root)

    on_exit(fn ->
      Application.delete_env(:agent_board, :dsh_profiles_dir)
      File.rm_rf!(root)

      if previous,
        do: Application.put_env(:agent_board, :superagent_provisioner, previous),
        else: Application.delete_env(:agent_board, :superagent_provisioner)

      if Process.alive?(pid), do: Agent.stop(pid)
    end)

    {:ok, repo} = Board.add_repository("fixture", "failed-panel")

    superagent =
      superagent!(repo, %{
        observed_state: "error",
        # Longer than the summary limit: only the failed-setup rule shows it whole.
        last_error:
          "@bot cannot push to fixture/failed-panel. Add the bot at https://github.com/fixture/failed-panel/settings/access with write access, wait for it to accept the invitation, and try again.",
        provision_failed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        checkout_path: "/tmp/checkout",
        source_profile: "superagent"
      })

    {:ok, view, html} =
      live(conn, "/?repo=fixture/failed-panel&panel=settings&section=projects")

    assert html =~ "a configuração não terminou"
    # The reason is said in words where the problem shows, once, with the way out beside it.
    assert has_element?(view, "#project-#{superagent.id}-error p", "@bot cannot push")
    refute has_element?(view, "#project-#{superagent.id} details", "Detalhes técnicos")

    assert has_element?(
             view,
             "#project-#{superagent.id}-error #project-retry_provision_superagent-#{superagent.id}-trigger"
           )

    trigger = "#project-retry_provision_superagent-#{superagent.id}-trigger"
    assert view |> element(trigger) |> render() =~ "Tentar de novo"
    refute has_element?(view, "#project-start_superagent-#{superagent.id}-trigger")

    view |> element(trigger) |> render_click()
    assert render(view) =~ "Provisionar de novo"
    assert Repo.get!(Superagent, superagent.id).observed_state == "error"

    view
    |> element("#project-retry_provision_superagent-#{superagent.id}-confirm")
    |> render_click()

    # The provisioning runs in a task; under a loaded suite 100 ms was not enough.
    _ = render_async(view, 2_000)

    retried = Repo.get!(Superagent, superagent.id)
    assert is_nil(retried.provision_failed_at)
    assert retried.observed_state == "starting"
  end

  # A repository tracked without an agent is still a project: it gets a row,
  # and its button fills the add form, which asks before creating the agent.
  test "a repository tracked without an agent is listed and can get one", %{conn: conn} do
    {:ok, with_agent} = Board.add_repository("fixture", "with-agent")
    superagent!(with_agent, %{observed_state: "ready"})
    {:ok, tracked} = Board.add_repository("fixture", "tracked-only")

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/with-agent&panel=settings&section=projects")

    row = "#tracked-#{tracked.id}"
    assert has_element?(view, row, "fixture/tracked-only")
    assert has_element?(view, row, "Sem agente")
    refute has_element?(view, "#tracked-#{with_agent.id}")
    assert has_element?(view, ".ab-projects__summary", "1 sem agente")

    view |> element("#{row} button", "Conectar agente") |> render_click()

    assert_patch(view, "/?panel=settings&path=agent&repo=fixture%2Fwith-agent&section=projects")
    assert has_element?(view, "#agent-install")
    assert has_element?(view, "#track-repo input[name=owner][value=fixture]")
    assert has_element?(view, "#track-repo input[name=name][value=tracked-only]")
    refute has_element?(view, "#add-project-confirm")
  end

  test "a board with only tracked repositories is not empty", %{conn: conn} do
    {:ok, _tracked} = Board.add_repository("fixture", "only-tracked")

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/only-tracked&panel=settings&section=projects")

    refute has_element?(view, ".ab-projects__empty")
    assert has_element?(view, ".ab-projects__list", "fixture/only-tracked")
  end

  test "a failed setup whose reason is not a sentence keeps the summary and the details", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "failed-term")

    superagent =
      superagent!(repo, %{
        observed_state: "error",
        last_error: "{:manager, 1, \"" <> String.duplicate("traceback ", 20) <> "\"}",
        provision_failed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        checkout_path: "/tmp/checkout",
        source_profile: "superagent"
      })

    {:ok, view, _html} = live(conn, "/?repo=fixture/failed-term&panel=settings&section=projects")

    refute has_element?(view, "#project-#{superagent.id}-error p", "traceback")
    assert has_element?(view, "#project-#{superagent.id}-error details code", "traceback")
  end
end
