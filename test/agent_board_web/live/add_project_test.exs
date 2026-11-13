defmodule AgentBoardWeb.AddProjectTest do
  @moduledoc "One confirmed action tracks the repository and provisions its own superagent."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Superagents}
  alias AgentBoard.Superagents.FakeProvisioner

  defp with_sources(fun) do
    profiles = Path.join(System.tmp_dir!(), "dsh-profiles-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(profiles, "superagent"))

    File.write!(
      Path.join([profiles, "superagent", "cordis.patch.yml"]),
      "webserver:\n  port: 3082\n- id: dsh-superagent\n"
    )

    previous = Application.get_env(:agent_board, :dsh_profiles_dir)
    previous_provisioner = Application.get_env(:agent_board, :superagent_provisioner)
    Application.put_env(:agent_board, :dsh_profiles_dir, profiles)
    Application.put_env(:agent_board, :superagent_provisioner, FakeProvisioner)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :dsh_profiles_dir, previous),
        else: Application.delete_env(:agent_board, :dsh_profiles_dir)

      if previous_provisioner,
        do: Application.put_env(:agent_board, :superagent_provisioner, previous_provisioner),
        else: Application.delete_env(:agent_board, :superagent_provisioner)

      File.rm_rf!(profiles)
    end)

    fun.()
  end

  test "add project previews the provision sentence and creates the superagent", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "base")

    with_sources(fn ->
      {:ok, view, _html} =
        live(conn, ~p"/?repo=fixture/base&panel=settings&section=repositories&path=agent")

      view
      |> form("#track-repo", %{
        "owner" => "fixture",
        "name" => "fresh",
        "path" => "/tmp/fresh-checkout",
        "create_agent" => "true",
        "workers" => "5"
      })
      |> render_submit()

      assert has_element?(view, "#add-project-confirm", "Provisionar o DeepSeek")

      view |> element("#add-project-confirm button", "Criar superagente") |> render_click()
      Process.sleep(150)
      _ = render(view)

      assert repository = Board.repository_by_slug("fixture/fresh")
      assert superagent = Superagents.get_by_repository(repository)
      assert superagent.profile =~ "superagent-fresh"
      assert superagent.max_workers == 5
    end)
  end

  test "leaving the agent path cancels its pending confirmation", %{conn: conn} do
    with_sources(fn ->
      {:ok, view, _} = live(conn, "/?panel=settings&section=projects&path=agent")
      view |> form("#track-repo", %{"owner" => "fixture", "name" => "switch"}) |> render_submit()
      assert has_element?(view, "#add-project-confirm")
      view |> element(".ab-projects nav a", "Usar só o GitHub") |> render_click()
      refute has_element?(view, "#add-project-confirm")
      view |> element(".ab-projects nav a", "Conectar o Super Agent") |> render_click()
      refute has_element?(view, "#add-project-confirm")
      assert Superagents.list() == []
    end)
  end

  test "the workers typed above the agent's limit are provisioned at the limit", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "base-limit")

    with_sources(fn ->
      {:ok, view, _html} =
        live(conn, ~p"/?repo=fixture/base-limit&panel=settings&section=repositories&path=agent")

      view
      |> form("#track-repo", %{
        "owner" => "fixture",
        "name" => "limit",
        "path" => "/tmp/limit-checkout",
        "create_agent" => "true",
        "workers" => "20"
      })
      |> render_submit()

      view |> element("#add-project-confirm button", "Criar superagente") |> render_click()
      Process.sleep(150)
      _ = render(view)

      repository = Board.repository_by_slug("fixture/limit")
      assert Superagents.get_by_repository(repository).max_workers == 16
    end)
  end

  test "track only adds the repository without a confirmation or an agent", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "base-track")

    with_sources(fn ->
      {:ok, view, _html} =
        live(conn, ~p"/?repo=fixture/base-track&panel=settings&section=repositories")

      refute has_element?(view, "#track-repo [name=create_agent]")

      view
      |> form("#track-repo", %{"owner" => "fixture", "name" => "tracked"})
      |> render_submit()

      refute has_element?(view, "#add-project-confirm")
      assert repository = Board.repository_by_slug("fixture/tracked")
      refute Superagents.get_by_repository(repository)
    end)
  end

  describe "a machine with no agent yet" do
    setup do
      empty =
        Path.join(System.tmp_dir!(), "dsh-profiles-empty-#{System.unique_integer([:positive])}")

      File.mkdir_p!(empty)

      for {key, value} <- [dsh_profiles_dir: empty, superagent_provisioner: FakeProvisioner] do
        previous = Application.get_env(:agent_board, key)
        Application.put_env(:agent_board, key, value)

        on_exit(fn ->
          if previous,
            do: Application.put_env(:agent_board, key, previous),
            else: Application.delete_env(:agent_board, key)
        end)
      end

      on_exit(fn ->
        Application.delete_env(:agent_board, :fake_first_ready)
        File.rm_rf!(empty)
      end)

      :ok
    end

    defp add_first(conn, name) do
      {:ok, _repo} = Board.add_repository("fixture", "base-#{name}")

      {:ok, view, _html} =
        live(conn, ~p"/?repo=fixture/base-#{name}&panel=settings&section=repositories&path=agent")

      view
      |> form("#track-repo", %{
        "owner" => "fixture",
        "name" => name,
        "path" => "/tmp/#{name}",
        "create_agent" => "true",
        "workers" => "2"
      })
      |> render_submit()

      view
    end

    test "the form offers to install the first agent, and the confirmed click does it", %{
      conn: conn
    } do
      view = add_first(conn, "first")

      assert has_element?(
               view,
               "#add-project-confirm",
               "Instalar o primeiro agente DeepSeek desta máquina, para first?"
             )

      assert has_element?(view, "#add-project-confirm", "baixa e compila o código do agente")
      # Asking installed nothing.
      refute Superagents.get_by_repository(Board.repository_by_slug("fixture/first"))

      view |> element("#add-project-confirm button", "Instalar o agente") |> render_click()
      Process.sleep(150)
      _ = render(view)

      assert %{profile: "superagent-first", source_profile: nil, max_workers: 2} =
               Superagents.get_by_repository(Board.repository_by_slug("fixture/first"))

      assert %{outcome: "ok", decision: "confirmed"} =
               AgentBoard.Repo.get_by!(AgentBoard.Actions.Decision,
                 action: "install_first_superagent"
               )
    end

    test "without dsh the form says what the machine lacks and asks nothing", %{conn: conn} do
      Application.put_env(:agent_board, :fake_first_ready, {:error, :dsh_missing})
      view = add_first(conn, "nodsh")

      assert render(view) =~ "o comando dsh do DeepSeek Harness não está nela"
      refute has_element?(view, "#add-project-confirm")
    end

    test "without a sign-in for the agent the form points at AI and setup", %{conn: conn} do
      Application.put_env(:agent_board, :fake_first_ready, {:error, :bot_missing})
      view = add_first(conn, "nobot")

      assert render(view) =~ "ele ainda não tem login no GitHub"
      refute has_element?(view, "#add-project-confirm")
    end
  end
end
