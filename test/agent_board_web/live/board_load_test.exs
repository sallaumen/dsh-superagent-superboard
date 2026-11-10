defmodule AgentBoardWeb.BoardLoadTest do
  @moduledoc """
  When the board reads everything again: once per render of the page, on
  :board_updated (a burst of them once), and never for a patch inside the
  same repository.
  """
  # Not async: the burst test sets the global :board_reload_ms knob.
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task
  alias AgentBoardWeb.BoardNavigation

  setup do
    {:ok, repo} = Board.add_repository("fixture", "load-#{System.unique_integer([:positive])}")
    slug = "#{repo.owner}/#{repo.name}"
    id = "board-load-#{slug}"

    :telemetry.attach(
      id,
      [:agent_board, :board, :load, :stop],
      &__MODULE__.loaded/4,
      {self(), slug}
    )

    on_exit(fn -> :telemetry.detach(id) end)

    %{repo: repo}
  end

  def loaded(_event, _measurements, %{repository: slug}, {pid, slug}),
    do: send(pid, :board_loaded)

  def loaded(_event, _measurements, _metadata, _config), do: :ok

  test "the page and its connection each read the board once", %{conn: conn, repo: repo} do
    {:ok, _view, _html} = live(conn, BoardNavigation.path(repo))

    assert loads() == 2
  end

  test "opening a task and closing it leave the board as it was loaded", %{
    conn: conn,
    repo: repo
  } do
    task = task(repo, 31, "Medir FPS", "ready")
    {:ok, view, _html} = live(conn, BoardNavigation.path(repo))
    loads()

    view |> element("article[phx-click=open][phx-value-id='#{task.id}']") |> render_click()
    assert_patch(view)
    assert has_element?(view, "#conversation-title", "Medir FPS")

    render_patch(view, BoardNavigation.path(repo))
    refute has_element?(view, "#conversation")

    assert loads() == 0
  end

  test "a broadcast reads the board again", %{conn: conn, repo: repo} do
    {:ok, view, _html} = live(conn, BoardNavigation.path(repo))
    loads()

    send(view.pid, :board_updated)
    render(view)

    assert loads() == 1
  end

  test "a burst of broadcasts reads the board once, after it", %{conn: conn, repo: repo} do
    Application.put_env(:agent_board, :board_reload_ms, 50)
    on_exit(fn -> Application.put_env(:agent_board, :board_reload_ms, 0) end)

    {:ok, view, _html} = live(conn, BoardNavigation.path(repo))
    loads()

    task(repo, 32, "Chegou na rajada", "ready")
    for _ <- 1..3, do: send(view.pid, :board_updated)
    render(view)
    assert loads() == 0

    assert_receive :board_loaded, 1_000
    assert render(view) =~ "Chegou na rajada"
    refute_receive :board_loaded, 200
  end

  defp loads(count \\ 0) do
    receive do
      :board_loaded -> loads(count + 1)
    after
      0 -> count
    end
  end

  defp task(repo, number, title, state) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: state,
      state_changed_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end
end
