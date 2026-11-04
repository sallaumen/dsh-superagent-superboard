defmodule AgentBoardWeb.BoardLiveTest do
  @moduledoc "The board's UI: the columns render and the tasks can be created."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  test "the board renders the columns", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Running"
    assert html =~ "Merged"
    assert html =~ "Queued"
  end

  test "the board renders the tracked repository", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "sallaumen/arena-rogue"
  end

  test "the board renders without a repository", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "nothing here"
  end
end
