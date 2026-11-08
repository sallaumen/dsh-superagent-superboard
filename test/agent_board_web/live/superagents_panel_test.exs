defmodule AgentBoardWeb.SuperagentsPanelTest do
  @moduledoc "The read-only superagents panel: one card per project, state and last error."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Superagents}

  defp superagent!(repo, attrs) do
    {:ok, superagent} =
      Superagents.create(
        Map.merge(
          %{
            repository_id: repo.id,
            profile: "superagent-#{repo.name}",
            port: 3190 + rem(repo.id, 1000),
            state_dir: "/tmp/superagent-#{repo.name}"
          },
          attrs
        )
      )

    superagent
  end

  test "renders a card with status, port, workers and error", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "panel")
    superagent = superagent!(repo, %{observed_state: "error", last_error: "github: sem acesso"})
    {:ok, _} = Superagents.observe(superagent, %{state: "error", detail: "github: sem acesso"})

    {:ok, _view, html} = live(conn, "/?repo=fixture/panel&panel=superagents")

    assert html =~ "Superagents DeepSeek"
    assert html =~ "fixture/panel"
    assert html =~ "superagent-panel"
    assert html =~ "erro"
    assert html =~ "github: sem acesso"
  end

  test "an empty board says no superagent is registered", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "empty-panel")
    {:ok, _view, html} = live(conn, "/?repo=fixture/empty-panel&panel=superagents")

    assert html =~ "Nenhum superagent registrado"
  end
end
