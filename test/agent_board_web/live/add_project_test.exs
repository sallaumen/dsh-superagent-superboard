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
      "webserver:\n  port: 3082\n"
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
      {:ok, view, _html} = live(conn, ~p"/?repo=fixture/base&panel=settings&section=repositories")

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

  test "the workers typed above the agent's limit are provisioned at the limit", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "base-limit")

    with_sources(fn ->
      {:ok, view, _html} =
        live(conn, ~p"/?repo=fixture/base-limit&panel=settings&section=repositories")

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

      view |> element("#track-repo input[name=create_agent]") |> render_click()

      view
      |> form("#track-repo", %{"owner" => "fixture", "name" => "tracked"})
      |> render_submit()

      refute has_element?(view, "#add-project-confirm")
      assert repository = Board.repository_by_slug("fixture/tracked")
      refute Superagents.get_by_repository(repository)
    end)
  end

  test "without a working profile the form explains instead of failing silently", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "base-no-source")

    empty =
      Path.join(System.tmp_dir!(), "dsh-profiles-empty-#{System.unique_integer([:positive])}")

    File.mkdir_p!(empty)

    previous = Application.get_env(:agent_board, :dsh_profiles_dir)
    Application.put_env(:agent_board, :dsh_profiles_dir, empty)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :dsh_profiles_dir, previous),
        else: Application.delete_env(:agent_board, :dsh_profiles_dir)

      File.rm_rf!(empty)
    end)

    {:ok, view, _html} =
      live(conn, ~p"/?repo=fixture/base-no-source&panel=settings&section=repositories")

    view
    |> form("#track-repo", %{
      "owner" => "fixture",
      "name" => "nosource",
      "path" => "/tmp/x",
      "create_agent" => "true"
    })
    |> render_submit()

    assert has_element?(view, ".toast", "Nenhum perfil DSH de trabalho nesta máquina")
    refute has_element?(view, "#add-project-confirm")
  end
end
