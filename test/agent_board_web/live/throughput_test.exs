defmodule AgentBoardWeb.ThroughputTest do
  @moduledoc "The throughput strip: observed counts, honest unknowns, live on broadcast."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}
  alias Ecto.Adapters.SQL.Sandbox

  defp allow_view(view) do
    Sandbox.allow(AgentBoard.Repo, self(), view.pid)
    view
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp task!(repo, attrs) do
    %Task{}
    |> Task.changeset(Map.merge(%{repository_id: repo.id, kind: "issue", title: "t"}, attrs))
    |> Repo.insert!()
  end

  defp pull!(repo, attrs) do
    %PullRequest{}
    |> PullRequest.changeset(
      Map.merge(%{repository_id: repo.id, title: "pr", state: "merged"}, attrs)
    )
    |> Repo.insert!()
  end

  defp board(conn, slug \\ "sallaumen/arena-rogue") do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    task!(repo, %{number: 1, state: "done", state_changed_at: ago(120)})
    task!(repo, %{number: 2, state: "queued"})
    pull!(repo, %{number: 10, opened_at: ago(900), merged_at: ago(60)})
    {:ok, view, html} = live(conn, ~p"/?repo=#{slug}")
    {repo, allow_view(view), html}
  end

  test "the strip counts what the tables hold and names what it never read", %{conn: conn} do
    {_repo, _view, html} = board(conn)

    assert html =~ ~s(id="sec-flow")
    assert html =~ "Vazão"
    assert html =~ "calculado às"

    # 1 task done and 1 PR merged in the last hour; 1 task queued now.
    assert html =~ ~s(data-key="done" data-value="1")
    assert html =~ ~s(data-key="merged" data-value="1")
    assert html =~ ~s(data-key="queue" data-value="1")

    # Commits were never read and the orchestrator is switched off in test.
    assert html =~ ~s(data-key="commits" data-value="?")
    assert html =~ "ainda sem leitura dos commits"
    assert html =~ ~s(data-key="load" data-value="?")
    assert html =~ "orquestrador não configurado"

    # The sparkline carries its values for assistive technology.
    assert html =~ "PRs mesclados por hora nas últimas 24 h, da mais antiga à atual: "
    assert html =~ ~s(role="img")
  end

  test "a commit read of zero is a zero, not a question mark", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    task!(repo, %{number: 2, state: "queued"})
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"commits" => 0, "errors" => 0})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ ~s(data-key="commits" data-value="0")
    refute html =~ "ainda sem leitura dos commits"
  end

  test "the strip follows the board's broadcast", %{conn: conn} do
    {repo, view, html} = board(conn)
    assert html =~ ~s(data-key="merged" data-value="1")

    pull!(repo, %{number: 11, opened_at: ago(300), merged_at: ago(30)})
    Board.broadcast(repo.id)

    assert render(view) =~ ~s(data-key="merged" data-value="2")
  end

  test "the clock label follows the reader's offset", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    task!(repo, %{number: 2, state: "queued"})

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"board_tz_offset" => 180})
      |> live(~p"/?repo=sallaumen/arena-rogue")

    html = render(allow_view(view))
    local = DateTime.utc_now() |> DateTime.add(-180 * 60, :second)
    assert html =~ "calculado às #{String.slice(Time.to_string(DateTime.to_time(local)), 0, 5)}"
  end

  test "an empty board has no strip", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    refute html =~ ~s(id="sec-flow")
  end
end
