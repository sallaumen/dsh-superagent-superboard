defmodule AgentBoardWeb.VoiceSpeechTest do
  @moduledoc "Who speaks and how much: the free browser voice by default, ElevenLabs when chosen."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.ElevenLabs.Usage
  alias AgentBoardWeb.VoiceSpeech

  defp voice(attrs) do
    Map.merge(
      %{
        id: "voz",
        configured: true,
        engine: "browser",
        replies: "short",
        language: "pt-BR",
        speed: 1.0
      },
      attrs
    )
  end

  test "the browser voice is the default, even with an ElevenLabs key" do
    assert {"speak", %{lang: "pt-BR", rate: 1.0, text: "Oi."}} =
             VoiceSpeech.push(voice(%{}), "Oi.", kind: :call)
  end

  test "mixed uses ElevenLabs only for calls; elevenlabs for everything" do
    assert {"voice_play", %{url: "/api/voice/stream?" <> _}} =
             VoiceSpeech.push(voice(%{engine: "mixed"}), "Travei em X.", kind: :call)

    assert {"speak", _} = VoiceSpeech.push(voice(%{engine: "mixed"}), "Tudo calmo.", kind: :reply)

    for kind <- [:call, :reply, :confirm, :narration] do
      assert {"voice_play", _} =
               VoiceSpeech.push(voice(%{engine: "elevenlabs"}), "Oi.", kind: kind)
    end
  end

  test "if the paid audio fails, the browser says what the browser voice would have said" do
    reply = "**Pronto.** O PR está em https://github.com/x/y/pull/1 e falta revisar."

    assert {"voice_play", %{fallback: fallback, text: ^reply}} =
             VoiceSpeech.push(voice(%{engine: "elevenlabs", speed: 1.2}), reply, kind: :reply)

    assert {"speak", ^fallback} =
             VoiceSpeech.push(voice(%{speed: 1.2}), reply, kind: :reply)

    refute fallback.text =~ "**"
    assert fallback.rate == 1.2
  end

  test "without a key everything goes to the browser" do
    assert {"speak", _} =
             VoiceSpeech.push(voice(%{engine: "elevenlabs", configured: false}), "Oi.",
               kind: :call
             )
  end

  test "a short reply speaks its first sentence and keeps the whole text to show" do
    text =
      "Três tarefas rodando e nada bloqueado. A fila tem cinco e as últimas entregas foram boas."

    assert {"speak", %{text: "Três tarefas rodando e nada bloqueado.", display: ^text}} =
             VoiceSpeech.push(voice(%{}), text, kind: :reply)

    assert {"speak", %{text: ^text}} =
             VoiceSpeech.push(voice(%{replies: "full"}), text, kind: :reply)
  end

  test "a proposal or confirmation is always spoken whole" do
    text = "Entendi. Vou criar no arena rogue a tarefa: Placar. Posso criar?"
    assert {"speak", %{text: ^text}} = VoiceSpeech.push(voice(%{}), text, kind: :confirm)
  end

  test "a very short first sentence takes the next one along" do
    assert VoiceSpeech.spoken(
             "Oi! Tudo calmo por aqui. Mais detalhes no painel.",
             :reply,
             "short"
           ) ==
             "Oi! Tudo calmo por aqui."
  end

  test "past the day's character cap the paid engines fall back to the free voice" do
    previous = Application.get_env(:agent_board, :elevenlabs_daily_char_cap)
    Application.put_env(:agent_board, :elevenlabs_daily_char_cap, 100)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :elevenlabs_daily_char_cap, previous),
        else: Application.delete_env(:agent_board, :elevenlabs_daily_char_cap)
    end)

    assert {"voice_play", _} = VoiceSpeech.push(voice(%{engine: "elevenlabs"}), "Oi.")
    Usage.record_tts(150, :paid)
    assert {"speak", _} = VoiceSpeech.push(voice(%{engine: "elevenlabs"}), "Oi.")
  end
end
