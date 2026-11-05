defmodule AgentBoardWeb.TaskTitleTest do
  @moduledoc "A task without a URL must still be visible."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  test "a task without a url still renders its title", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 101,
      title: "Invisible before",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Invisible before"
  end
end
