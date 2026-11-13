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

  test "mark all clears the current replies, while a later edit becomes unread again", %{
    conn: conn
  } do
    {:ok, first} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, second} = Board.add_repository("sallaumen", "o_colmex")

    first_task = task(first, 81, "Revisar interface", "ready")
    second_task = task(second, 82, "Responder à Yasme", "question")
    comment(first_task, 4001, "Primeira resposta")
    comment(second_task, 4002, "Segunda resposta")

    {:ok, view, _html} = live(conn, "/?repo=#{first.owner}/#{first.name}")
    assert has_element?(view, "#message-inbox summary[aria-label='Mensagens da Yasme, 2 novas']")
    assert has_element?(view, "#attention-inbox .ab-hub-item", "Responder à Yasme")

    view |> element("#message-inbox .ab-hub-menu__mark-all") |> render_click()
    assert_push_event(view, "messages_seen", %{versions: versions})

    assert Map.keys(versions) |> Enum.sort() ==
             Enum.sort(["#{first_task.id}", "#{second_task.id}"])

    assert has_element?(
             view,
             "#message-inbox summary[aria-label='Mensagens da Yasme, nenhuma nova']"
           )

    assert has_element?(
             view,
             "#message-inbox .ab-hub-menu__mark-all[disabled]",
             "Marcar todas como vistas"
           )

    assert has_element?(view, "#attention-inbox .ab-hub-item", "Responder à Yasme")

    view
    |> element("#message-inbox .ab-hub-menu__filters button[phx-value-filter='unread']")
    |> render_click()

    assert has_element?(
             view,
             "#message-inbox .ab-hub-menu__filters button[aria-pressed='true']",
             "Não lidas"
           )

    assert has_element?(view, "#message-inbox .ab-hub-menu__empty", "Você está em dia")
    refute has_element?(view, "#message-inbox .ab-hub-item")

    comment(second_task, 4002, "Resposta editada depois da leitura")
    Board.broadcast(second.id)

    assert has_element?(view, "#message-inbox summary[aria-label='Mensagens da Yasme, 1 nova']")
    assert has_element?(view, "#message-inbox .ab-hub-item", "Resposta editada depois da leitura")
    refute has_element?(view, "#message-inbox .ab-hub-item", "Primeira resposta")
  end

  test "one reply can be marked seen without opening its task or clearing another reply", %{
    conn: conn
  } do
    {:ok, first} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, second} = Board.add_repository("sallaumen", "o_colmex")
    first_task = task(first, 83, "Primeiro diálogo", "running")
    second_task = task(second, 84, "Segundo diálogo", "question")
    comment(first_task, 5001, "Primeira resposta")
    comment(second_task, 5002, "Segunda resposta")

    version =
      Board.inbox().messages |> Enum.find(&(&1.task_id == first_task.id)) |> Map.fetch!(:version)

    {:ok, view, _html} = live(conn, "/?repo=#{first.owner}/#{first.name}")

    view
    |> element("#message-inbox .ab-hub-row__read[phx-value-id='#{first_task.id}']")
    |> render_click()

    task_id = first_task.id
    assert_push_event(view, "message_seen", %{task_id: ^task_id, version: ^version, quick: true})
    assert has_element?(view, "#message-inbox summary[aria-label='Mensagens da Yasme, 1 nova']")
    refute has_element?(view, "#message-inbox .ab-hub-row__read[phx-value-id='#{first_task.id}']")

    assert has_element?(
             view,
             "#message-inbox .ab-hub-row__read[phx-value-id='#{second_task.id}']"
           )

    assert has_element?(view, "#attention-inbox .ab-hub-item", "Segundo diálogo")
    refute has_element?(view, "#conversation")
  end

  test "an outdated read action keeps the edited reply unread", %{conn: conn} do
    {:ok, repository} = Board.add_repository("sallaumen", "o_colmex")
    task = task(repository, 85, "Resposta que mudou", "running")
    comment(task, 5003, "Resposta inicial")
    old_version = Board.inbox().messages |> hd() |> Map.fetch!(:version)
    {:ok, view, _html} = live(conn, "/?repo=#{repository.owner}/#{repository.name}")

    comment(task, 5003, "Resposta editada")

    render_click(view, "mark_inbox_message_seen", %{
      "id" => Integer.to_string(task.id),
      "version" => old_version
    })

    assert has_element?(view, "#flash-group #flash-error", "A resposta mudou")
    assert has_element?(view, "#message-inbox summary[aria-label='Mensagens da Yasme, 1 nova']")
    assert has_element?(view, "#message-inbox .ab-hub-item", "Resposta editada")
  end

  defp task(repository, number, title, state) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repository.id,
      kind: "issue",
      number: number,
      title: title,
      state: state
    })
    |> Repo.insert!()
  end

  defp comment(task, id, body) do
    Board.upsert_comment(
      task,
      %{"id" => id, "body" => body, "user" => %{"login" => "sallaumen-agent"}},
      "sallaumen-agent"
    )
  end
end
