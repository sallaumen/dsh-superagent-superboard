defmodule AgentBoardWeb.BoardLoadTest do
  @moduledoc """
  When the board reads everything again: once per render of the page, on
  :board_updated, and never for a patch inside the same repository.
  """
  use AgentBoardWeb.ConnCase, async: true

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
