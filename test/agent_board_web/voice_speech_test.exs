defmodule AgentBoardWeb.VoiceSpeechTest do
  @moduledoc "Only ElevenLabs speaks; unavailable paid audio leaves the written answer."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.ElevenLabs.Usage
  alias AgentBoardWeb.VoiceSpeech

  defp voice(attrs \\ %{}) do
    Map.merge(
      %{id: "voz", configured: true, replies: "short", language: "pt-BR"},
      attrs
    )
  end

  test "available ElevenLabs speaks all requested kinds" do
    for kind <- [:call, :reply, :confirm] do
      assert {"voice_play", %{url: "/api/voice/stream?" <> _, text: "Oi."}} =
               VoiceSpeech.push(voice(), "Oi.", kind: kind)
    end
  end

  test "no key means no speech event" do
    assert VoiceSpeech.push(voice(%{configured: false}), "Oi.", kind: :call) == nil
  end

  test "the first sentence of a short reply is spoken; the whole reply stays displayed" do
    text = "Três tarefas rodando e nada bloqueado. A fila tem cinco."

    assert {"voice_play", %{url: url, text: ^text}} =
             VoiceSpeech.push(voice(), text, kind: :reply)

    assert URI.decode_query(URI.parse(url).query)["text"] ==
             "Três tarefas rodando e nada bloqueado."

    assert {"voice_play", %{url: full_url}} =
             VoiceSpeech.push(voice(%{replies: "full"}), text, kind: :reply)

    assert URI.decode_query(URI.parse(full_url).query)["text"] == text
  end

  test "a confirmation is spoken whole and never carries a browser fallback" do
    text = "Entendi. Vou criar a tarefa: Placar. Posso criar?"
    assert {"voice_play", payload} = VoiceSpeech.push(voice(), text, kind: :confirm)
    assert URI.decode_query(URI.parse(payload.url).query)["text"] == text
    refute Map.has_key?(payload, :fallback)
  end

  test "past the character cap stays silent" do
    previous = Application.get_env(:agent_board, :elevenlabs_daily_char_cap)
    Application.put_env(:agent_board, :elevenlabs_daily_char_cap, 100)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :elevenlabs_daily_char_cap, previous),
        else: Application.delete_env(:agent_board, :elevenlabs_daily_char_cap)
    end)

    assert {"voice_play", _} = VoiceSpeech.push(voice(), "Oi.")
    Usage.record_tts(150, :paid)
    assert VoiceSpeech.push(voice(), "Oi.") == nil
  end
end
