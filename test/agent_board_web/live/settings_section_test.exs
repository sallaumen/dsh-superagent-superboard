defmodule AgentBoardWeb.SettingsSectionTest do
  @moduledoc "The settings section lives in the URL, so an update restart returns to it."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.Board
  alias AgentBoardWeb.BoardNavigation

  test "settings_path keeps the section and the repository" do
    {:ok, repo} = Board.add_repository("fixture", "sections")

    assert BoardNavigation.settings_path(repo, "version") ==
             "/?panel=settings&repo=fixture%2Fsections&section=version"

    assert BoardNavigation.settings_path(repo, nil) ==
             "/?panel=settings&repo=fixture%2Fsections"
  end

  test "the URL section opens the right pane and survives a nav change", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "sections-live")

    {:ok, view, _html} =
      live(conn, ~p"/?repo=fixture/sections-live&panel=settings&section=version")

    assert has_element?(view, "section[aria-labelledby=settings-version-title]")
    refute has_element?(view, "section[aria-labelledby=settings-version-title][hidden]")
    assert has_element?(view, "section[aria-labelledby=settings-dispatch-title][hidden]")

    view
    |> element(".settings-nav button[phx-value-section=dispatch]")
    |> render_click()

    assert_patch(view, "/?panel=settings&repo=fixture%2Fsections-live&section=dispatch")
    refute has_element?(view, "section[aria-labelledby=settings-dispatch-title][hidden]")
  end
end
