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
    view |> element("[data-task]") |> render_click()
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

  test "a question shows its sentence first; only Mandar posts it", %{conn: conn} = c do
    Req.Test.stub(@stub, &Req.Test.json(&1, %{"id" => 5, "user" => %{"login" => "me"}}))
    {view, task} = open(conn, c.task)

    view |> element("#ask-agent") |> render_submit(%{"body" => "Rodou os testes?"})

    phrase = Actions.phrase(:ask_task, %{task: task, question: "Rodou os testes?"})
    assert has_element?(view, "#ask-confirm-q", phrase)
    refute has_element?(view, "#ask-agent")
    assert Repo.aggregate(Comment, :count, :id) == 0

    view |> element("#ask-confirm-go") |> render_click()

    assert has_element?(view, "#flash-info", "Question sent")
    assert %Comment{github_id: 5} = Repo.get_by!(Comment, task_id: task.id)
    assert %Decision{action: "ask_task", decision: "confirmed", evidence: "phrase"} = last()
  end

  test "going back from a question keeps the text and records the no", %{conn: conn} = c do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called") end)
    {view, task} = open(conn, c.task)

    view |> element("#ask-agent") |> render_submit(%{"body" => "Rodou os testes?"})
    view |> element("#ask-confirm-cancel") |> render_click()

    assert has_element?(view, "#ask-body", "Rodou os testes?")
    assert %Decision{action: "ask_task", decision: "refused", detail: "declined"} = last()
    assert last().subject == "##{task.number}"
  end

  test "archive is yellow: one click, recorded as automatic", %{conn: conn} = c do
    {view, task} = open(conn, c.task)

    view |> element("#conversation button", "Arquivar") |> render_click()

    assert Repo.get!(Task, task.id).archived
    assert %Decision{action: "archive_task", decision: "automatic", via: "ui"} = last()
  end
end
