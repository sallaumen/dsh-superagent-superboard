defmodule AgentBoardWeb.SettingsActivityTest do
  @moduledoc "Settings → System → Activity: grouped reads, repeated errors and the future-clock note."
  use AgentBoardWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Event

  setup do
    {:ok, repo} = Board.add_repository("fixture", "activity")
    %{repo: repo, path: "/?repo=fixture/activity&panel=settings&section=system"}
  end

  test "consecutive reads without change become one row with Show", %{
    conn: conn,
    repo: repo,
    path: path
  } do
    for _ <- 1..2 do
      Board.log_event(repo.id, "sync", "fixture/activity", %{"issues" => 10, "pulls" => 100})
    end

    {:ok, view, _html} = live(conn, path)

    assert has_element?(view, ".settings-activity__row", "2 leituras sem mudança")
    assert has_element?(view, ".settings-activity__row", "10 issues · 100 PRs")
    assert has_element?(view, ".settings-activity__more summary", "Mostrar")
  end

  test "the same errors in every read become one halt row with the reasons on demand", %{
    conn: conn,
    repo: repo,
    path: path
  } do
    for _ <- 1..2 do
      Board.log_event(repo.id, "sync", "fixture/activity", %{
        "issues" => 10,
        "pulls" => 100,
        "errors" => 6
      })
    end

    Board.log_event(repo.id, "issue_error", "#12", %{"reason" => "boom 1"})
    Board.log_event(repo.id, "pull_error", "#3", %{"reason" => "boom 2"})

    {:ok, view, _html} = live(conn, path)

    assert has_element?(view, ".settings-activity__row.is-halt", "6 erros em toda leitura")
    assert has_element?(view, ".settings-activity__row", "Os mesmos 6 se repetem nas 2 leituras")

    view |> element("button", "Ver os erros") |> render_click()

    assert has_element?(view, ".settings-activity__error-list", "boom 1")
    assert has_element?(view, ".settings-activity__error-list", "boom 2")
  end

  test "all events in the future get one stale note instead of row stamps", %{
    conn: conn,
    repo: repo,
    path: path
  } do
    for _ <- 1..2 do
      Board.log_event(repo.id, "sync", "fixture/activity", %{"issues" => 1, "pulls" => 1})
    end

    future = DateTime.add(DateTime.utc_now(), 86_400, :second) |> DateTime.truncate(:second)

    Repo.update_all(from(e in Event, where: e.repository_id == ^repo.id),
      set: [inserted_at: future]
    )

    {:ok, view, _html} = live(conn, path)

    assert has_element?(view, ".settings-activity__future", "à frente do relógio do board")
    assert has_element?(view, ".settings-activity__time", "—")
  end
end
