defmodule AgentBoardWeb.MessageInboxTest do
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  test "message and attention windows stay separate and open the right dialogue", %{conn: conn} do
    {:ok, first} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, second} = Board.add_repository("sallaumen", "o_colmex")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: second.id,
        kind: "issue",
        number: 72,
        title: "Resposta em outro projeto",
        state: "blocked"
      })
      |> Repo.insert!()

    Board.upsert_comment(
      task,
      %{
        "id" => 3001,
        "body" => "Tenho uma pergunta para você",
        "user" => %{"login" => "sallaumen-agent"}
      },
      "sallaumen-agent"
    )

    {:ok, view, _html} = live(conn, "/?repo=#{first.owner}/#{first.name}")

    assert has_element?(view, "#message-inbox summary[aria-label='Mensagens da Yasme, 1 nova']")
    assert has_element?(view, "#message-inbox .ab-hub-item", "Tenho uma pergunta para você")
    assert has_element?(view, "#attention-inbox .ab-hub-item", "Resposta em outro projeto")

    view |> element("#message-inbox .ab-hub-item") |> render_click()

    assert_patch(
      view,
      "/?panel=conversation&repo=sallaumen%2Fo_colmex&tab=conversa&task=#{task.id}"
    )

    assert has_element?(view, "#conversation .ab-msg", "Tenho uma pergunta para você")
    task_id = task.id
    assert_push_event(view, "message_seen", %{task_id: ^task_id, version: _})

    assert has_element?(
             view,
             "#message-inbox summary[aria-label='Mensagens da Yasme, nenhuma nova']"
           )
  end

  test "a reply from another project updates the open board", %{conn: conn} do
    {:ok, first} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, second} = Board.add_repository("sallaumen", "o_colmex")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: second.id,
        kind: "issue",
        number: 73,
        title: "Outra resposta",
        state: "running"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/?repo=#{first.owner}/#{first.name}")
    refute has_element?(view, "#message-inbox .ab-hub-item")

    Board.upsert_comment(
      task,
      %{"id" => 3002, "body" => "Resposta ao vivo", "user" => %{"login" => "sallaumen-agent"}},
      "sallaumen-agent"
    )

    Board.broadcast(second.id)
    assert has_element?(view, "#message-inbox .ab-hub-item", "Resposta ao vivo")
  end
end
