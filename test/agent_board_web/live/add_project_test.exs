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
        "path" => "/tmp/fresh-checkout"
      })
      |> render_submit()

      assert has_element?(view, "#add-project-confirm", "Provisionar o DeepSeek")

      view |> element("#add-project-confirm button", "Criar superagente") |> render_click()
      Process.sleep(150)
      _ = render(view)

      assert repository = Board.repository_by_slug("fixture/fresh")
      assert superagent = Superagents.get_by_repository(repository)
      assert superagent.profile =~ "superagent-fresh"
      assert superagent.max_workers == 3
    end)
  end

  test "track only adds the repository without a confirmation or an agent", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "base-track")

    with_sources(fn ->
      {:ok, view, _html} =
        live(conn, ~p"/?repo=fixture/base-track&panel=settings&section=repositories")

      view
      |> form("#track-repo-only", %{"owner" => "fixture", "name" => "tracked"})
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
    |> form("#track-repo", %{"owner" => "fixture", "name" => "nosource", "path" => "/tmp/x"})
    |> render_submit()

    assert has_element?(view, ".toast", "Nenhum perfil DSH de trabalho nesta máquina")
    refute has_element?(view, "#add-project-confirm")
  end
end
