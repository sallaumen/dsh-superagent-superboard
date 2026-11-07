defmodule AgentBoard.VoiceTest do
  @moduledoc "The voice: the spoken summary and the owner's voice settings."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Settings
  alias AgentBoard.Voice
  alias AgentBoard.Voice.Phrases

  defp board(running \\ 0, ready \\ 0, merged \\ 0, queued \\ 0) do
    %{
      running: List.duplicate(%{}, running),
      ready: List.duplicate(%{}, ready),
      merged: List.duplicate(%{}, merged),
      queued: List.duplicate(%{}, queued)
    }
  end

  defp at(hour) do
    {:ok, dt, _} =
      DateTime.from_iso8601("2026-11-04T#{String.pad_leading("#{hour}", 2, "0")}:00:00Z")

    dt
  end

  test "a calm board says so, in Portuguese by default" do
    text = Voice.summary(board(), now: at(9))
    assert text =~ "Bom dia"
    assert text =~ "Tudo tranquilo"
  end

  test "the counts are spoken, what needs the owner first" do
    text =
      Voice.summary(Map.put(board(1, 0, 8, 2), :question, [%{}]), now: at(14))

    assert text ==
             "Boa tarde. No quadro: 1 esperando sua resposta, 1 em andamento, 2 na fila e 8 entregas recentes."
  end

  test "English is one setting away" do
    text = Voice.summary(board(0, 0, 1, 1), now: at(20), language: "en-US")
    assert text == "Good evening. On the board: 1 queued and 1 recent merge."
  end

  test "a blocked-only board is not called calm" do
    text = Voice.summary(%{blocked: [%{}, %{}]}, now: at(9))
    assert text =~ "2 bloqueadas"
    refute text =~ "tranquilo"
  end

  test "the greeting follows the owner's clock, not UTC" do
    # 01:00 UTC is 22:00 in São Paulo (180 minutes west of UTC).
    assert Voice.summary(board(), now: at(1), tz_offset: 180) =~ "Boa noite"
    assert Voice.summary(board(), now: at(13), tz_offset: 180) =~ "Bom dia"
    assert Voice.summary(board(), now: at(18), tz_offset: 180) =~ "Boa tarde"
  end

  test "the task confirmation is one line in the voice language" do
    assert Voice.task_summary("Add a boss", "stop", "pt-BR") == "Parei Add a boss."
    assert Voice.task_summary("Add a boss", "archive", "en-US") == "Archived Add a boss."
  end

  test "language, volume and attention persist and refuse bad values" do
    assert Voice.language() == "pt-BR"
    assert Voice.volume() == 100
    assert Voice.attention?()

    assert :ok = Voice.put_language("en-US")
    assert Voice.language() == "en-US"
    assert {:error, :invalid_language} = Voice.put_language("klingon")
    assert Voice.language() == "en-US"

    assert :ok = Voice.put_volume("35")
    assert Voice.volume() == 35
    assert {:error, :invalid_volume} = Voice.put_volume("120")
    assert {:error, :invalid_volume} = Voice.put_volume("loud")
    assert Voice.volume() == 35

    assert :ok = Voice.put_attention(false)
    refute Voice.attention?()
  end

  test "a stored value outside the offer falls back to the default" do
    :ok = Settings.put("voice_language", "xx")
    :ok = Settings.put("voice_volume", "900")

    assert Voice.language() == Phrases.default_language()
    assert Voice.volume() == 100
  end

  test "every attention pool has ten distinct phrases with the title" do
    for lang <- Enum.map(Phrases.languages(), & &1.id), kind <- Phrases.attention_kinds() do
      pool = Phrases.attention_pool(lang, kind)
      assert length(pool) == 10
      assert length(Enum.uniq(pool)) == 10
      assert Enum.all?(pool, &String.contains?(&1, "%{t}"))
    end
  end

  test "a long title is cut at a word for speech" do
    title = "Refatorar o módulo de sincronização para isolar cada item e registrar os erros"
    short = Phrases.short_title(title)

    assert String.length(short) <= 60
    assert String.starts_with?(title, short)
    refute short =~ ~r/\s\z/
  end

  test "speed, intonation, pause and sounds persist and refuse bad values" do
    assert Voice.speed() == 1.0
    assert Voice.style() == "natural" and Voice.stability() == 0.5
    assert Voice.pause() == "normal" and Voice.pause_ms() == 1200
    assert Voice.earcons?()

    assert :ok = Voice.put_speed("1.1")
    assert Voice.speed() == 1.1
    assert {:error, :invalid_speed} = Voice.put_speed("2")
    assert {:error, :invalid_speed} = Voice.put_speed("rápido")

    assert :ok = Voice.put_style("expressive")
    assert Voice.stability() == 0.3
    assert {:error, :invalid_style} = Voice.put_style("robô")

    assert :ok = Voice.put_pause("long")
    assert Voice.pause_ms() == 1800
    assert {:error, :invalid_pause} = Voice.put_pause("eterna")

    assert :ok = Voice.put_earcons(false)
    refute Voice.earcons?()
  end

  test "input, engine, replies and narration default to the cheap choices" do
    assert Voice.input() == "wispr"
    assert Voice.engine() == "browser"
    assert Voice.replies() == "short"
    refute Voice.narrate?()

    assert :ok = Voice.put_input("microphone")
    assert :ok = Voice.put_engine("mixed")
    assert :ok = Voice.put_replies("full")
    assert :ok = Voice.put_narrate(true)

    assert {Voice.input(), Voice.engine(), Voice.replies(), Voice.narrate?()} ==
             {"microphone", "mixed", "full", true}

    assert {:error, :invalid_input} = Voice.put_input("telepatia")
    assert {:error, :invalid_engine} = Voice.put_engine("robô")
    assert {:error, :invalid_replies} = Voice.put_replies("longas")
  end
end
