defmodule AgentBoardWeb.VoiceConversationLiveTest do
  @moduledoc """
  The hands-free conversation in the LiveView: a finished utterance is
  answered out loud, a newer one supersedes an older one, a slow one times
  out, and the log is a record, not a step.
  """
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.AI.Engines.Scripted
  alias AgentBoard.{Board, Conversation}

  setup do
    previous =
      for key <- [
            :ai_rehearsal,
            :ai_engine,
            :ai_api_key,
            :ai_script,
            :elevenlabs_api_key,
            :voice_turn_timeout_ms
          ],
          into: %{},
          do: {key, Application.get_env(:agent_board, key)}

    Application.put_env(:agent_board, :ai_rehearsal, false)
    Application.put_env(:agent_board, :ai_engine, Scripted)
    Application.put_env(:agent_board, :ai_api_key, "test-key")
    Application.put_env(:agent_board, :elevenlabs_api_key, "test-key")

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:agent_board, key),
          else: Application.put_env(:agent_board, key, value)
      end
    end)

    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    :ok
  end

  defp reply(text, action \\ "reply") do
    Scripted.answer(%{
      "reply" => text,
      "action" => action,
      "request" => "",
      "task_number" => 0,
      "repository" => ""
    })
  end

  defp script(fun), do: Application.put_env(:agent_board, :ai_script, fun)

  defp spoken(url),
    do: url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("text")

  defp board(conn) do
    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    view
  end

  test "a finished utterance is answered out loud, with no draft to review", %{conn: conn} do
    script(fn %{name: :voice_agent} -> reply("Duas tarefas rodando e nada bloqueado.") end)
    view = board(conn)

    render_hook(view, "voice_turn", %{"text" => "Como está o quadro?"})
    render_async(view)

    assert_push_event(view, "voice_play", %{url: url, listen: false})
    assert spoken(url) == "Duas tarefas rodando e nada bloqueado."
    refute has_element?(view, "#board-page[data-panel=voice]")

    assert [%{role: "owner", text: "Como está o quadro?"}, %{role: "agent"}] =
             Conversation.recent()
  end

  test "a reply that asks for a yes opens the microphone again", %{conn: conn} do
    script(fn %{name: :voice_agent} -> reply("", "stop_task") end)
    view = board(conn)

    {:ok, task} =
      %AgentBoard.Board.Task{}
      |> AgentBoard.Board.Task.changeset(%{
        repository_id: Board.list_repositories() |> hd() |> Map.fetch!(:id),
        number: 7,
        title: "Placar",
        state: "running",
        kind: "issue"
      })
      |> AgentBoard.Repo.insert()

    script(fn %{name: :voice_agent} ->
      Scripted.answer(%{
        "reply" => "",
        "action" => "stop_task",
        "request" => "",
        "task_number" => task.number,
        "repository" => ""
      })
    end)

    render_hook(view, "voice_turn", %{"text" => "para a tarefa sete"})
    render_async(view)

    assert_push_event(view, "voice_play", %{url: url, listen: true})
    assert spoken(url) == "Parar a tarefa 7, Placar? Posso?"
  end

  test "without an ElevenLabs key the browser speaks in the voice language", %{conn: conn} do
    Application.put_env(:agent_board, :elevenlabs_api_key, "")
    script(fn %{name: :voice_agent} -> reply("Oi! Tudo certo.") end)
    view = board(conn)

    render_hook(view, "voice_turn", %{"text" => "oi"})
    render_async(view)

    assert_push_event(view, "speak", %{text: "Oi! Tudo certo.", lang: "pt-BR", listen: false})
  end

  test "a newer utterance supersedes a slower one", %{conn: conn} do
    test_pid = self()

    script(fn %{name: :voice_agent, prompt: prompt} ->
      # The memory carries the first utterance too: match the utterance field.
      if prompt =~ ~s("utterance": "primeira pergunta") do
        send(test_pid, :first_started)
        Process.sleep(300)
        reply("Resposta velha.")
      else
        reply("Resposta nova.")
      end
    end)

    view = board(conn)
    render_hook(view, "voice_turn", %{"text" => "primeira pergunta"})
    assert_receive :first_started, 1_000
    render_hook(view, "voice_turn", %{"text" => "segunda pergunta"})
    render_async(view, 1_000)
    Process.sleep(400)

    assert_push_event(view, "voice_play", %{url: url})
    assert spoken(url) == "Resposta nova."
    refute_push_event(view, "voice_play", %{url: _}, 100)
  end

  test "a turn that takes too long is dropped and said so", %{conn: conn} do
    Application.put_env(:agent_board, :voice_turn_timeout_ms, 50)

    script(fn %{name: :voice_agent} ->
      Process.sleep(400)
      reply("Tarde demais.")
    end)

    view = board(conn)
    render_hook(view, "voice_turn", %{"text" => "oi"})

    assert_push_event(view, "voice_play", %{url: url}, 1_000)
    assert spoken(url) == "Demorei demais e parei. Pode me pedir de novo."
    Process.sleep(450)
    refute_push_event(view, "voice_play", %{url: _}, 100)
  end

  test "in the composer, the microphone still dictates the request", %{conn: conn} do
    view = board(conn)
    view |> element("#open-create") |> render_click()

    render_hook(view, "voice_turn", %{"text" => "Corrigir o placar"})

    assert render(view) =~ "Corrigir o placar"
    assert Conversation.recent() == []
  end

  test "the voice panel shows the conversation, takes typed words and forgets", %{conn: conn} do
    script(fn %{name: :voice_agent} -> reply("Pode deixar.") end)
    {:ok, view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue&panel=voice")
    assert html =~ "Aperte espaço duas vezes"

    view |> element("#voice-chat-form") |> render_submit(%{"text" => "lembra do placar"})
    render_async(view)

    assert has_element?(view, "#voice-chat-turns [data-role=owner]", "lembra do placar")
    assert has_element?(view, "#voice-chat-turns [data-role=agent]", "Pode deixar.")

    view |> element("#voice-forget") |> render_click()
    assert Conversation.recent() == []
    refute has_element?(view, "#voice-chat-turns")
  end

  test "without a model the simple commands still answer", %{conn: conn} do
    Application.put_env(:agent_board, :ai_api_key, "")
    view = board(conn)

    render_hook(view, "voice_turn", %{"text" => "status"})
    render_async(view)

    assert_push_event(view, "voice_play", %{url: _url})
    assert [%{role: "owner"}, %{role: "agent", action: "command"}] = Conversation.recent()
  end
end
