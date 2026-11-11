defmodule AgentBoardWeb.BoardActionsTest do
  @moduledoc """
  The gate on the screen (`AgentBoard.Actions`): a red action runs only with
  the sentence the screen showed, the sentence is the registry's (the one
  the voice says), and a no is recorded.
  """
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Actions, Board, Repo}
  alias AgentBoard.Actions.Decision
  alias AgentBoard.Board.{Comment, Task}

  @stub AgentBoardWeb.BoardActionsTest.Stub

  setup do
    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn -> Application.delete_env(:agent_board, :github_client) end)

    {:ok, repo} = Board.add_repository("fixture", "gate")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 7,
        title: "Placar",
        state: "queued"
      })
      |> Repo.insert!()

    %{repo: repo, task: task}
  end

  defp open(conn, task) do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/gate")
    view |> element(~s([data-panel-trigger][phx-value-id="#{task.id}"])) |> render_click()
    assert has_element?(view, "#conversation")
    {view, task}
  end

  defp last, do: hd(Actions.recent(1))

  test "a stop without the sentence is refused and nothing reaches GitHub", %{conn: conn} = c do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called") end)
    {view, task} = open(conn, c.task)

    # An event without the confirmation (an old tab, a forged click).
    render_hook(view, "act", %{"id" => to_string(task.id), "action" => "stop"})

    assert has_element?(view, "#flash-error", "Nada foi feito")
    refute Repo.get!(Task, task.id).stopped
    assert %Decision{action: "stop_task", decision: "refused", detail: "unconfirmed"} = last()
  end

  test "Parar shows the registry's sentence, the one the voice says", %{conn: conn} = c do
    {view, task} = open(conn, c.task)

    view |> element("#stop-#{task.id}-trigger") |> render_click()

    assert has_element?(
             view,
             "#stop-#{task.id} .ab-act__question",
             Actions.phrase(:stop_task, %{task: task})
           )

    view |> element("#stop-#{task.id} button", "Cancelar") |> render_click()

    assert %Decision{action: "stop_task", decision: "refused", detail: "declined", via: "ui"} =
             last()
  end

  test "Enviar posts the typed question in one step and records its authorization",
       %{conn: conn} = c do
    Req.Test.stub(@stub, &Req.Test.json(&1, %{"id" => 5, "user" => %{"login" => "me"}}))
    {view, task} = open(conn, c.task)

    view |> element("#ask-agent") |> render_submit(%{"body" => "Rodou os testes?"})
    render_async(view, 2_000)

    assert has_element?(view, "#flash-info", "Pergunta enviada")
    refute has_element?(view, "#ask-confirm")
    assert %Comment{github_id: 5} = Repo.get_by!(Comment, task_id: task.id)
    assert %Decision{action: "ask_task", decision: "confirmed", evidence: "phrase"} = last()
  end

  test "answering an unblock request closes it immediately and after reload", %{conn: conn} = c do
    task = blocked_workpad(c.task)
    Req.Test.stub(@stub, &Req.Test.json(&1, %{"id" => 6, "user" => %{"login" => "me"}}))
    {view, _task} = open(conn, task)
    assert has_element?(view, "#unblock-panel")

    view |> element("#ask-agent") |> render_submit(%{"body" => "Use o menu restrito."})
    refute has_element?(view, "#unblock-panel")

    render_async(view, 2_000)
    refute has_element?(view, "#unblock-panel")

    {reloaded, _task} = open(conn, task)
    refute has_element?(reloaded, "#unblock-panel")
  end

  test "a failed unblock reply restores the draft and the unblock request", %{conn: conn} = c do
    task = blocked_workpad(c.task)
    parent = self()

    Req.Test.stub(@stub, fn conn ->
      send(parent, {:request_started, self()})

      receive do
        :release_request -> :ok
      end

      Req.Test.json(conn, %{})
    end)

    {view, _task} = open(conn, task)

    view |> element("#ask-agent") |> render_submit(%{"body" => "Use o menu restrito."})
    assert_receive {:request_started, request_pid}, 2_000
    refute has_element?(view, "#unblock-panel")

    send(request_pid, :release_request)
    render_async(view, 2_000)
    assert has_element?(view, "#unblock-panel")
    assert has_element?(view, "#ask-body", "Use o menu restrito.")
    assert has_element?(view, ".ab-compose__error", "não chegou ao GitHub")
    assert Repo.aggregate(Comment, :count, :id) == 1
  end

  test "a late failure in task A does not replace task B's draft or block its send",
       %{conn: conn} = c do
    {view, task_a} = open(conn, c.task)

    task_b =
      %Task{}
      |> Task.changeset(%{
        repository_id: c.repo.id,
        kind: "issue",
        number: 8,
        title: "Outra tarefa",
        state: "queued"
      })
      |> Repo.insert!()

    Req.Test.stub(@stub, fn conn ->
      if String.contains?(conn.request_path, "/issues/#{task_a.number}/") do
        Process.sleep(100)
        Req.Test.json(conn, %{})
      else
        Req.Test.json(conn, %{"id" => 8, "user" => %{"login" => "me"}})
      end
    end)

    view |> element("#ask-agent") |> render_submit(%{"body" => "Falha na tarefa A"})
    render_hook(view, "open", %{"id" => to_string(task_b.id)})
    assert_patch(view)

    view |> element("#ask-agent") |> render_submit(%{"body" => "Mensagem da tarefa B"})
    render_async(view, 2_000)

    assert %Comment{github_id: 8} = Repo.get_by!(Comment, task_id: task_b.id)
    refute has_element?(view, ".ab-compose__error", "não chegou ao GitHub")
    refute has_element?(view, "#ask-body", "Falha na tarefa A")

    render_hook(view, "open", %{"id" => to_string(task_a.id)})
    assert_patch(view)
    assert has_element?(view, "#ask-body", "Falha na tarefa A")
    assert has_element?(view, ".ab-compose__error", "não chegou ao GitHub")
  end

  test "archive is yellow: one click, recorded as automatic", %{conn: conn} = c do
    {view, task} = open(conn, c.task)

    view |> element("#conversation button", "Arquivar") |> render_click()

    assert Repo.get!(Task, task.id).archived
    assert %Decision{action: "archive_task", decision: "automatic", via: "ui"} = last()
  end

  defp blocked_workpad(task) do
    task =
      task
      |> Task.changeset(%{state: "blocked", state_changed_at: DateTime.utc_now()})
      |> Repo.update!()

    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: 4,
      author: "sallaumen-agent",
      kind: "agent",
      body: "## Relatório do agente\n\n### Pergunta\nDevo usar o menu restrito?"
    })
    |> Repo.insert!()

    task
  end
end
