defmodule AgentBoardWeb.VoiceConversationLiveTest do
  @moduledoc """
  The hands-free conversation in the LiveView: a finished utterance is
  answered out loud, a newer one supersedes an older one, a slow one times
  out, and the log is a record, not a step.
  """
  use AgentBoardWeb.ConnCase, async: false

  # Failures are exercised on purpose; their log lines show only if a test fails.
  @moduletag capture_log: true

  import Phoenix.LiveViewTest

  alias AgentBoard.AI.Engines.Scripted
  alias AgentBoard.{Board, Conversation}
  alias AgentBoard.Board.{Comment, Task}
  alias AgentBoardWeb.VoiceConversation

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
    # These tests cover the paid voice and whole replies; the defaults are
    # the browser voice and short replies (covered in voice_speech_test).
    :ok = AgentBoard.Settings.put("voice_engine", "elevenlabs")
    :ok = AgentBoard.Settings.put("voice_replies", "full")
    :ok
  end

  defp reply(text, action \\ "reply") do
    Scripted.answer(%{
      "reply" => text,
      "action" => action,
      "request" => "",
      "title" => "",
      "details" => [],
      "question" => "",
      "task_number" => 0,
      "repository" => "",
      "lookup" => "",
      "direct" => false,
      "executor" => ""
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
    render_async(view, 1_000)

    assert_push_event(view, "voice_play", %{url: url, listen: false}, 1_000)
    assert spoken(url) == "Duas tarefas rodando e nada bloqueado."
    refute has_element?(view, "#board-page[data-panel=voice]")

    assert [%{role: "owner", text: "Como está o quadro?"}, %{role: "agent"}] =
             Conversation.recent()
  end

  test "a reply that asks for a yes opens the microphone again", %{conn: conn} do
    script(fn %{name: :voice_agent} -> reply("", "stop_task") end)
    view = board(conn)

    {:ok, task} =
      %Task{}
      |> Task.changeset(%{
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
        "title" => "",
        "details" => [],
        "question" => "",
        "task_number" => task.number,
        "repository" => "",
        "lookup" => "",
        "direct" => false,
        "executor" => ""
      })
    end)

    render_hook(view, "voice_turn", %{"text" => "para a tarefa sete"})
    render_async(view, 1_000)

    assert_push_event(view, "voice_play", %{url: url, listen: true}, 1_000)

    assert spoken(url) ==
             "Parar a tarefa 7, “Placar”? O board fecha a issue e marca a tarefa como parada; " <>
               "um passo que o agente já começou termina antes."
  end

  test "without an ElevenLabs key the browser speaks in the voice language", %{conn: conn} do
    Application.put_env(:agent_board, :elevenlabs_api_key, "")
    script(fn %{name: :voice_agent} -> reply("Oi! Tudo certo.") end)
    view = board(conn)

    render_hook(view, "voice_turn", %{"text" => "oi"})
    render_async(view, 1_000)

    assert_push_event(
      view,
      "speak",
      %{text: "Oi! Tudo certo.", lang: "pt-BR", listen: false},
      1_000
    )
  end

  test "a newer utterance supersedes a slower one", %{conn: conn} do
    test_pid = self()

    script(fn %{name: :voice_agent, prompt: prompt} ->
      # The memory carries the first utterance too: match the utterance field.
      if prompt =~ ~r/"utterance":\s*"primeira pergunta"/ do
        send(test_pid, {:first_started, self()})

        receive do
          :answer -> reply("Resposta velha.")
        end
      else
        reply("Resposta nova.")
      end
    end)

    view = board(conn)
    render_hook(view, "voice_turn", %{"text" => "primeira pergunta"})
    assert_receive {:first_started, first}, 1_000
    render_hook(view, "voice_turn", %{"text" => "segunda pergunta"})
    render_async(view, 1_000)

    # The superseded turn's answer, if its task is still alive, is dropped.
    send(first, :answer)
    render_async(view, 1_000)

    assert_push_event(view, "voice_play", %{url: url}, 1_000)
    assert spoken(url) == "Resposta nova."
    refute_push_event(view, "voice_play", %{url: _}, 100)
  end

  test "a turn that takes too long is dropped and said so", %{conn: conn} do
    Application.put_env(:agent_board, :voice_turn_timeout_ms, 50)

    # The timeout cancels the turn, which kills the model's task.
    script(fn %{name: :voice_agent} -> Process.sleep(:infinity) end)

    view = board(conn)
    render_hook(view, "voice_turn", %{"text" => "oi"})

    assert_push_event(view, "voice_play", %{url: url}, 1_000)
    assert spoken(url) == "Demorei demais e parei. Pode me pedir de novo."
    render_async(view, 1_000)
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
    assert html =~ "SuperBoard Skills"

    view |> element("#voice-chat-form") |> render_submit(%{"text" => "lembra do placar"})
    assert_push_event(view, "voice_chat_clear", %{text: "lembra do placar"})
    render_async(view, 1_000)

    assert has_element?(view, "#voice-chat-turns [data-role=owner]", "lembra do placar")
    assert has_element?(view, "#voice-chat-turns [data-role=agent]", "Pode deixar.")

    view |> element("#voice-forget") |> render_click()
    assert Conversation.recent() == []
    refute has_element?(view, "#voice-chat-turns")
  end

  test "the voice panel lists what can be asked, and an example can be sent", %{conn: conn} do
    script(fn %{name: :voice_agent} -> reply("Nada falhando agora.") end)
    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue&panel=voice")

    assert has_element?(view, "#voice-commands:not([open])")
    assert has_element?(view, "#voice-commands h4", "Execuções do agente")
    assert has_element?(view, "#voice-commands .sb-skills__item[data-mode=direct]", "desfaz")

    view
    |> element(~s(.sb-skills__card[phx-value-text="O que está falhando?"]))
    |> render_click()

    render_async(view, 1_000)
    refute_push_event(view, "voice_chat_clear", %{}, 50)
    assert_push_event(view, "voice_play", %{url: url}, 1_000)
    assert spoken(url) == "Nada falhando agora."
    assert [%{role: "owner", text: "O que está falhando?"}, _] = Conversation.recent()
  end

  test "a spoken ajuda opens the command list without the model", %{conn: conn} do
    script(fn _ -> flunk("the model must not be called") end)
    view = board(conn)

    render_hook(view, "voice_turn", %{"text" => "ajuda"})
    render_async(view, 1_000)

    assert_push_event(view, "voice_play", %{url: url}, 1_000)
    assert spoken(url) =~ "A lista completa está na tela."
    assert has_element?(view, "#board-page[data-panel=voice]")
    assert has_element?(view, "#voice-commands[open]")
  end

  test "without a model the simple commands still answer", %{conn: conn} do
    Application.put_env(:agent_board, :ai_api_key, "")
    view = board(conn)

    render_hook(view, "voice_turn", %{"text" => "status"})
    render_async(view, 1_000)

    assert_push_event(view, "voice_play", %{url: _url}, 1_000)
    assert [%{role: "owner"}, %{role: "agent", action: "command"}] = Conversation.recent()
  end

  test "Escape while the agent thinks drops the turn without a reply", %{conn: conn} do
    test_pid = self()

    # Esc cancels the turn, which kills the model's task.
    script(fn %{name: :voice_agent} ->
      send(test_pid, :thinking)
      Process.sleep(:infinity)
    end)

    view = board(conn)
    render_hook(view, "voice_turn", %{"text" => "oi"})
    assert_receive :thinking, 1_000
    render_hook(view, "voice_cancel_turn", %{})
    render_async(view, 1_000)

    refute_push_event(view, "voice_play", %{url: _}, 100)
  end

  test "the history shows how long the agent took", %{conn: conn} do
    script(fn %{name: :voice_agent} -> reply("Pode deixar.") end)
    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue&panel=voice")

    view |> element("#voice-chat-form") |> render_submit(%{"text" => "oi"})
    render_async(view, 1_000)

    assert has_element?(view, "#voice-chat-turns [data-role=agent] .voice-chat-time", "pensou em")
  end

  test "a spoken mais baixo lowers the volume the player uses at once", %{conn: conn} do
    script(fn _ -> flunk("the model must not be called") end)
    {:ok, view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    assert html =~ ~s(data-volume="100")

    render_hook(view, "voice_turn", %{"text" => "mais baixo"})
    render_async(view, 1_000)

    assert render(view) =~ ~s(data-volume="80")
    assert_push_event(view, "voice_play", %{url: url}, 1_000)
    assert spoken(url) == "Pronto, mais baixo."
  end

  defp asked_task do
    repo = hd(Board.list_repositories())

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        number: 12,
        title: "Placar",
        state: "running",
        kind: "issue"
      })
      |> AgentBoard.Repo.insert!()

    {:ok, ask} =
      Conversation.record("agent", "Posso mandar?",
        proposal: %{"kind" => "ask_task", "task_id" => task.id, "number" => 12}
      )

    :ok = Conversation.settle(ask, "confirmed")
    ask = AgentBoard.Repo.reload!(ask)

    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: 77,
      kind: "agent",
      body: "<!-- dsh-superagent:x -->\nSim, rodei os testes e todos passaram."
    })
    |> Ecto.Changeset.force_change(
      :inserted_at,
      ask.updated_at |> DateTime.add(30) |> DateTime.truncate(:second)
    )
    |> AgentBoard.Repo.insert!()

    task
  end

  test "the coding agent's reply to a spoken question is said once", %{conn: conn} do
    view = board(conn)
    asked_task()

    send(view.pid, :board_updated)
    assert_push_event(view, "voice_play", %{url: url}, 1_000)

    assert spoken(url) ==
             "O agente da tarefa 12 respondeu: Sim, rodei os testes e todos passaram."

    send(view.pid, :board_updated)
    refute_push_event(view, "voice_play", %{url: _}, 100)
    assert [%{action: "agent_answered"} | _] = Enum.reverse(Conversation.recent())
  end

  test "with the calls for attention off, the reply waits silently", %{conn: conn} do
    :ok = AgentBoard.Settings.put("voice_attention", "0")
    view = board(conn)
    asked_task()

    send(view.pid, :board_updated)
    refute_push_event(view, "voice_play", %{url: _}, 100)
    assert [_reply] = Conversation.arrived_answers()
  end

  test "the spoken summary drops markers and keeps a few sentences" do
    long = "🤖 Resposta automática do agente\n" <> String.duplicate("Primeira frase longa. ", 20)
    summary = VoiceConversation.answer_summary(long)

    refute summary =~ "🤖"
    assert String.length(summary) <= 241
    assert String.ends_with?(summary, ".")
  end
end
