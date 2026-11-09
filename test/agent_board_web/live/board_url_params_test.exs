defmodule AgentBoardWeb.BoardUrlParamsTest do
  @moduledoc """
  The URL is input: an address someone edited, or an old link, opens the board
  on what it can find. It never answers a 500 or takes the socket down.
  """
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  @too_big "99999999999999999999999"

  setup do
    {:ok, repo} = Board.add_repository("fixture", "urls")
    %{repo: repo}
  end

  for query <- [
        "repo[a]=b",
        "repo[]=x",
        "panel[a]=b",
        "view[a]=b",
        "repo=fixture/urls&panel=conversation&task[a]=1",
        "repo=fixture/urls&panel=conversation&task[]=1",
        "repo=fixture/urls&panel=conversation&task=abc",
        "repo=fixture/urls&panel=conversation&task=-1",
        "repo=fixture/urls&panel=conversation&task=#{@too_big}",
        "repo=fixture/urls&panel=conversation",
        "repo=fixture/urls&panel=conversation&task=1&tab[a]=b",
        "repo=a%00/b",
        "repo=sem-barra",
        "repo=nada/nada"
      ] do
    test "/?#{query} opens the board without the panel", %{conn: conn} do
      {:ok, view, html} = live(conn, "/?" <> unquote(query))

      refute html =~ "panel-conversation"
      assert Process.alive?(view.pid)
      assert render(view) =~ "urls"
    end
  end

  test "a patch to an id past the database's range keeps the socket", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?repo=fixture/urls")

    render_patch(view, "/?repo=fixture/urls&panel=conversation&task=#{@too_big}")

    assert Process.alive?(view.pid)
  end

  test "the API answers 404 for an id past the database's range", %{conn: conn} do
    conn = patch(conn, "/api/tasks/#{@too_big}", %{action: "archive"})

    assert json_response(conn, 404)
  end

  test "open_any with an id past the database's range is ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?repo=fixture/urls")

    render_hook(view, "open_any", %{"id" => @too_big})

    assert Process.alive?(view.pid)
  end

  describe "a board with no repository yet" do
    setup %{repo: repo} do
      AgentBoard.Repo.delete!(repo)
      :ok
    end

    test "Settings opens, because that is where the first repository is added", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      assert html =~ "Nenhum repositório acompanhado"

      view |> element("#board-settings") |> render_click()
      assert_patch(view, "/?panel=settings")
      assert has_element?(view, "#board-page[data-panel=settings]")

      view
      |> element("#track-repo")
      |> render_submit(%{"owner" => "fixture", "name" => "primeiro"})

      assert Board.repository_by_slug("fixture/primeiro")
      assert render(view) =~ "primeiro"
    end
  end
end
