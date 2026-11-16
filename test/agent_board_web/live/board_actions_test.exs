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
  alias AgentBoard.AI.Engines.Scripted
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

  test "an id that is not a number is refused, and the view stays up", %{conn: conn} = c do
    {view, _task} = open(conn, c.task)

    render_hook(view, "act", %{"id" => "abc", "action" => "archive"})

    assert has_element?(view, "#flash-error", "Não foi possível atualizar a tarefa")
    assert has_element?(view, "#conversation")
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

  test "a cancelled child stays visible until the owner selects a linked replacement or waives with a reason",
       %{conn: conn, task: task} do
    parent = task |> Ecto.Changeset.change(state: "blocked") |> Repo.update!()

    child = fn n, state, status ->
      Repo.insert!(%Task{
        repository_id: parent.repository_id,
        blocker_for_task_id: parent.id,
        kind: "issue",
        number: n,
        title: "Evidence #{n}",
        state: state,
        github_issue_status: status
      })
    end

    child.(11, "done", nil)
    old = child.(8, "closed", "not_planned")
    next = child.(9, "queued", "open")
    waive = child.(10, "closed", "not_planned")
    pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, json, conn} = Plug.Conn.read_body(conn)
      send(pid, {:decision_comment, Jason.decode!(json)["body"]})
      Req.Test.json(conn, %{"id" => 71, "user" => %{"login" => "me"}})
    end)

    {:ok, view, _} =
      live(conn, ~p"/?repo=fixture/gate&panel=conversation&tab=conversa&task=#{parent.id}")

    assert render(view) =~ "aguardando o GitHub confirmar o motivo do encerramento"
    id = "#requirement-#{parent.id}-#{old.id}"
    view |> element("#{id} [phx-value-mode=replace]") |> render_click()

    view
    |> form("#{id}-form", reason: "Same evidence, new device", replacement: to_string(next.id))
    |> render_submit()

    render_async(view)

    assert Repo.reload!(old).blocker_decision == %{
             "kind" => "replaced",
             "replacement" => 9,
             "reason" => "Same evidence, new device"
           }

    refute_received {:decision_comment, _}
    id = "#requirement-#{parent.id}-#{waive.id}"
    view |> element("#{id} [phx-value-mode=waive]") |> render_click()
    view |> form("#{id}-form", reason: "   ") |> render_submit()
    assert is_nil(Repo.reload!(waive).blocker_decision)
    view |> form("#{id}-form", reason: "Only for the internal demo") |> render_submit()
    render_async(view)
    assert_receive {:decision_comment, body}
    assert body =~ "Only for the internal demo"
    assert body =~ "#10"
    assert %{"kind" => "waived", "comment" => 71} = Repo.reload!(waive).blocker_decision

    {:ok, reloaded, _} =
      live(conn, ~p"/?repo=fixture/gate&panel=conversation&tab=conversa&task=#{parent.id}")

    assert render(reloaded) =~ "Only for the internal demo"
    refute has_element?(reloaded, "#{id} [phx-value-mode=waive]")
    params = %{task: parent, child: waive, choice: "waive", reason: "second submit"}

    assert {:error, :stale_blocker} =
             Actions.run(:resolve_blocker, params, Actions.owner(:ui),
               confirm: Actions.phrase(:resolve_blocker, params)
             )

    refute_received {:decision_comment, _}
  end

  test "reviewing a historical agent decision preserves its snapshot and the ordinary draft", %{
    conn: conn,
    task: task
  } do
    task = task |> Ecto.Changeset.change(state: "done") |> Repo.update!()

    source =
      Repo.insert!(%Comment{
        task_id: task.id,
        github_id: 801,
        author: "agent",
        kind: "agent",
        body: "Use control A. <!-- routing-marker -->"
      })

    ordinary =
      Repo.insert!(%Comment{
        task_id: task.id,
        github_id: 802,
        author: "owner",
        kind: "user",
        body: "Thanks"
      })

    me = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(me, {:review_post, conn.request_path, Jason.decode!(raw)["body"]})
      Req.Test.json(conn, %{"id" => 803, "user" => %{"login" => "owner"}})
    end)

    {:ok, view, _} =
      live(conn, ~p"/?repo=fixture/gate&panel=conversation&tab=conversa&task=#{task.id}")

    id = "#review-#{task.id}-#{source.id}"
    refute has_element?(view, "#review-#{task.id}-#{ordinary.id}")
    form(view, "#ask-agent", body: "Separate draft") |> render_change()
    view |> element("#{id} button", "Rever esta decisão") |> render_click()

    assert has_element?(
             view,
             "#{id} a[href='https://github.com/fixture/gate/issues/7#issuecomment-801']"
           )

    assert has_element?(view, "#{id} blockquote", "Use control A.")
    view |> element("#{id} form") |> render_submit(%{"reason" => "  "})
    refute_received {:review_post, _, _}
    assert has_element?(view, "#{id} [role=alert]")
    reason = "O controle B cobre o risco de dano."
    view |> form("#{id} form", reason: reason) |> render_submit()
    render_async(view, 2_000)
    assert_receive {:review_post, "/repos/fixture/gate/issues/7/comments", body}
    assert body =~ "#issuecomment-801"
    assert body =~ "> Use control A."
    assert body =~ reason
    assert body =~ "não altere o código"
    refute body =~ "routing-marker"
    assert has_element?(view, "#{id} [role=status]", "Revisão solicitada")
    assert has_element?(view, "#ask-body", "Separate draft")
    assert %Decision{action: "ask_task", decision: "confirmed", via: "ui"} = last()
    refute_received {:review_post, _, _}
  end

  test "the ask shows the model's answer", %{conn: conn} = c do
    Req.Test.stub(@stub, &Req.Test.json(&1, %{"id" => 6, "user" => %{"login" => "me"}}))

    previous =
      for key <- [:ai_engine, :ai_api_key, :ai_script],
          do: {key, Application.get_env(:agent_board, key)}

    Application.put_env(:agent_board, :ai_engine, Scripted)
    Application.put_env(:agent_board, :ai_api_key, "test-key")

    Application.put_env(:agent_board, :ai_script, fn %{name: :answer_question} ->
      Scripted.answer(%{"answer" => "O sync roda a cada minuto."})
    end)

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:agent_board, key),
          else: Application.put_env(:agent_board, key, value)
      end
    end)

    {view, task} = open(conn, c.task)
    view |> element("#ask-agent") |> render_submit(%{"body" => "por que demora?"})
    render_async(view, 2_000)

    assert %Comment{github_id: 6} = Repo.get_by!(Comment, task_id: task.id)

    # The model answers on another process; its arrival is an event.
    assert_push_event(view, "inspector:answer", %{task_id: _}, 2_000)
    assert render(view) =~ "O sync roda a cada minuto."
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
