defmodule AgentBoardWeb.AgentAccessPanelTest do
  @moduledoc "Settings → Agent access: who waits, who is cleared and how to add someone."
  use AgentBoardWeb.ConnCase, async: false

  import Ecto.Query, only: [order_by: 2, limit: 2]
  import Phoenix.LiveViewTest

  alias AgentBoard.Actions.Decision
  alias AgentBoard.{Board, Repo, Superagents}
  alias AgentBoard.Superagents.FakeManager

  @stub __MODULE__

  setup do
    {:ok, manager} = FakeManager.start()
    previous = Application.get_env(:agent_board, :superagent_manager)
    previous_client = Application.get_env(:agent_board, :github_client)
    Application.put_env(:agent_board, :superagent_manager, FakeManager)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.test", plug: {Req.Test, @stub}, retry: false)
    end)

    Req.Test.set_req_test_to_shared(%{})

    Req.Test.stub(@stub, fn conn ->
      cond do
        String.ends_with?(conn.request_path, "/collaborators") ->
          Req.Test.json(conn, [
            %{"login" => "fixture", "role_name" => "admin"},
            %{"login" => "amiga", "role_name" => "write"}
          ])

        String.ends_with?(conn.request_path, "/collaborators/nova") ->
          Plug.Conn.send_resp(conn, 204, "")

        String.ends_with?(conn.request_path, "/collaborators/fora") ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})

        String.ends_with?(conn.request_path, "/collaborators/nova/permission") ->
          Req.Test.json(conn, %{"role_name" => "write"})

        # GitHub answers read for anyone on a public repository.
        String.ends_with?(conn.request_path, "/collaborators/fora/permission") ->
          Req.Test.json(conn, %{"role_name" => "read"})

        String.ends_with?(conn.request_path, "/permission") ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})

        true ->
          Req.Test.json(conn, [])
      end
    end)

    on_exit(fn ->
      Req.Test.set_req_test_to_private(%{})

      if previous,
        do: Application.put_env(:agent_board, :superagent_manager, previous),
        else: Application.delete_env(:agent_board, :superagent_manager)

      if previous_client,
        do: Application.put_env(:agent_board, :github_client, previous_client),
        else: Application.delete_env(:agent_board, :github_client)

      if Process.alive?(manager), do: Agent.stop(manager)
    end)

    name = "access-ui-#{System.unique_integer([:positive])}"
    state_dir = Path.join(System.tmp_dir!(), name)
    File.mkdir_p!(state_dir)
    on_exit(fn -> File.rm_rf!(state_dir) end)

    {:ok, repo} = Board.add_repository("fixture", name)

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-#{name}",
        port: 3500 + rem(repo.id, 1000),
        state_dir: state_dir
      })

    FakeManager.put_access(superagent.id, ["fixture"])

    {:ok, repo: repo, superagent: superagent, state_dir: state_dir, path: path(repo)}
  end

  defp path(repo), do: "/?repo=#{repo.owner}/#{repo.name}&panel=settings&section=access"

  defp refused!(state_dir, login, number, trigger_id) do
    {:ok, conn} = Exqlite.Sqlite3.open(Path.join(state_dir, "orchestrator.sqlite"))

    for sql <- [
          "CREATE TABLE IF NOT EXISTS trigger (id TEXT PRIMARY KEY, value TEXT NOT NULL, at TEXT NOT NULL)",
          "CREATE TABLE IF NOT EXISTS decision (id TEXT PRIMARY KEY, thread TEXT NOT NULL, value TEXT NOT NULL)",
          "CREATE TABLE IF NOT EXISTS thread (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
        ] do
      :ok = Exqlite.Sqlite3.execute(conn, sql)
    end

    at = "2026-11-09T17:09:41.000Z"

    trigger = %{
      id: trigger_id,
      source: "github",
      actor: %{source: "github", id: login},
      human: true,
      addressed: "mention",
      url: "https://github.com/fixture/x/issues/#{number}",
      meta: %{number: number}
    }

    decision = %{kind: "ignore", at: at, reason: [%{code: "not_a_member", triggerId: trigger_id}]}

    insert!(conn, "trigger", [trigger_id, Jason.encode!(trigger), at])
    insert!(conn, "decision", ["d-#{trigger_id}", "github:#{number}", Jason.encode!(decision)])

    insert!(conn, "thread", [
      "github:#{number}",
      Jason.encode!(%{meta: %{title: "Uma issue"}})
    ])

    :ok = Exqlite.Sqlite3.close(conn)
  end

  defp insert!(conn, table, values) do
    marks = Enum.map_join(values, ", ", fn _ -> "?" end)
    {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO #{table} VALUES (#{marks})")
    :ok = Exqlite.Sqlite3.bind(statement, values)
    :done = Exqlite.Sqlite3.step(conn, statement)
    :ok = Exqlite.Sqlite3.release(conn, statement)
  end

  defp settled(view) do
    # Two rounds: the panel's read, then what it renders.
    _ = render_async(view)
    render_async(view)
  end

  defp cleared(superagent) do
    {:ok, %{allowed: allowed}} = FakeManager.access(superagent)
    Enum.map(allowed, & &1.login)
  end

  test "shows who is cleared, with the owner protected", context do
    %{conn: conn, path: path, superagent: superagent} = context
    FakeManager.put_access(superagent.id, ["fixture", "amiga"])

    {:ok, view, _html} = live(conn, path)
    html = settled(view)

    assert html =~ "@amiga"
    assert html =~ "@fixture"
    assert has_element?(view, "#settings-access-title")
    assert has_element?(view, ~s(button[id^="access-revoke-#{superagent.id}-amiga"]))
    refute has_element?(view, ~s(button[id^="access-revoke-#{superagent.id}-fixture"]))
  end

  test "the section stays out of the way until it is opened", context do
    %{conn: conn, repo: repo, superagent: superagent} = context
    FakeManager.put_access(superagent.id, ["fixture", "amiga"])

    {:ok, view, _html} = live(conn, "/?repo=#{repo.owner}/#{repo.name}")
    html = settled(view)

    refute html =~ "@amiga"
  end

  test "a refused mention becomes a request; clearing it runs the issue again", context do
    %{conn: conn, path: path, superagent: superagent, state_dir: state_dir} = context
    refused!(state_dir, "amiga", 1476, "trigger-1")

    {:ok, view, _html} = live(conn, path)
    html = settled(view)

    assert html =~ "@amiga"
    assert html =~ "#1476"
    assert html =~ "Uma issue"
    assert has_element?(view, ".settings-nav__mark--you", "1")

    id = "access-grant-run-#{superagent.id}-amiga"
    view |> element("##{id}-trigger") |> render_click()

    assert render(view) =~ "merge"
    assert render(view) =~ "#1476"
    # Nothing ran on the first click.
    assert cleared(superagent) == ["fixture"]

    view |> element("##{id}-confirm") |> render_click()
    html = settled(view)

    assert cleared(superagent) == ["fixture", "amiga"]
    assert FakeManager.requeued(superagent.id) == ["trigger-1"]
    refute has_element?(view, ".settings-nav__mark--you")
    assert html =~ "liberado"
    assert %Decision{action: "grant_agent_access", outcome: "ok"} = last_decision()
  end

  test "canceling a clearance records the no and changes nothing", context do
    %{conn: conn, path: path, superagent: superagent, state_dir: state_dir} = context
    refused!(state_dir, "amiga", 12, "trigger-2")

    {:ok, view, _html} = live(conn, path)
    settled(view)

    id = "access-grant-#{superagent.id}-amiga"
    view |> element("##{id}-trigger") |> render_click()
    view |> element("##{id} button", "Cancel") |> render_click()

    assert cleared(superagent) == ["fixture"]
    assert %Decision{decision: "refused", detail: "declined"} = last_decision()
  end

  test "setting a request aside takes it off the list", context do
    %{conn: conn, path: path, state_dir: state_dir, superagent: superagent} = context
    refused!(state_dir, "amiga", 12, "trigger-3")

    {:ok, view, _html} = live(conn, path)
    settled(view)

    view |> element(~s(button[phx-click="dismiss_request"])) |> render_click()
    settled(view)

    refute has_element?(view, ~s(button[phx-click="dismiss_request"]))
    assert cleared(superagent) == ["fixture"]
  end

  test "a malformed login stops at the form", context do
    %{conn: conn, path: path, superagent: superagent} = context

    {:ok, view, _html} = live(conn, path)
    settled(view)

    html = view |> element("#access-add-#{superagent.id}") |> render_submit(%{login: "@@"})

    assert html =~ "não é um login do GitHub"
    assert Repo.aggregate(AgentBoard.AgentAccess.Dismissal, :count) == 0
  end

  test "adding someone checks GitHub and asks before clearing", context do
    %{conn: conn, path: path, superagent: superagent} = context

    {:ok, view, _html} = live(conn, path)
    settled(view)

    view |> element("#access-add-#{superagent.id}") |> render_submit(%{login: "@nova"})
    html = settled(view)

    assert html =~ "@nova existe no GitHub"
    assert html =~ "write"

    id = "access-grant-new-#{superagent.id}-nova"
    view |> element("##{id}-trigger") |> render_click()
    view |> element("##{id}-confirm") |> render_click()
    settled(view)

    assert cleared(superagent) == ["fixture", "nova"]
  end

  test "a person without repository access is warned, not blocked", context do
    %{conn: conn, path: path, superagent: superagent} = context

    {:ok, view, _html} = live(conn, path)
    settled(view)

    view |> element("#access-add-#{superagent.id}") |> render_submit(%{login: "fora"})
    html = settled(view)

    assert html =~ "Sem acesso ao repositório"
    assert has_element?(view, "#access-grant-new-#{superagent.id}-fora-trigger")
  end

  test "an account GitHub does not have cannot be allowed", context do
    %{conn: conn, path: path, superagent: superagent} = context

    {:ok, view, _html} = live(conn, path)
    settled(view)

    view |> element("#access-add-#{superagent.id}") |> render_submit(%{login: "fantasma"})
    html = settled(view)

    assert html =~ "não tem nenhuma conta"
    refute has_element?(view, "#access-grant-new-#{superagent.id}-fantasma-trigger")
  end

  test "someone already allowed is told so", context do
    %{conn: conn, path: path, superagent: superagent} = context

    {:ok, view, _html} = live(conn, path)
    settled(view)

    html = view |> element("#access-add-#{superagent.id}") |> render_submit(%{login: "FIXTURE"})

    assert html =~ "já está liberado"
  end

  test "an agent that does not answer says so and offers no action", context do
    %{conn: conn, path: path, superagent: superagent} = context
    FakeManager.put_access(superagent.id, {:error, :econnrefused})

    {:ok, view, _html} = live(conn, path)
    html = settled(view)

    assert html =~ "não está respondendo"
    refute html =~ "Ninguém está liberado"
    refute html =~ "Ninguém mencionou"
    refute has_element?(view, "#access-add-#{superagent.id}")
  end

  test "a change announced elsewhere reaches the open section", context do
    %{conn: conn, path: path, superagent: superagent} = context

    {:ok, view, _html} = live(conn, path)
    refute settled(view) =~ "@colega"

    FakeManager.put_access(superagent.id, ["fixture", "colega"])
    Superagents.broadcast_access_changed()
    _ = render(view)

    assert settled(view) =~ "@colega"
  end

  test "a refused issue says why in the inspector", context do
    %{conn: conn, repo: repo, state_dir: state_dir} = context
    refused!(state_dir, "amiga", 1476, "trigger-4")

    {:ok, task} =
      %Board.Task{}
      |> Board.Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 1476,
        title: "Uma issue",
        state: "queued",
        author: "amiga",
        url: "https://github.com/fixture/x/issues/1476"
      })
      |> Repo.insert()

    {:ok, view, _html} =
      live(conn, "/?repo=#{repo.owner}/#{repo.name}&panel=conversation&task=#{task.id}")

    settled(view)

    assert has_element?(view, ".ab-insp__refused", "não está liberado")
    assert has_element?(view, "#open-agent-access")
  end

  defp last_decision do
    Decision
    |> order_by(desc: :id)
    |> limit(1)
    |> Repo.one()
  end
end
