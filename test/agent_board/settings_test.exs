defmodule AgentBoard.SettingsTest do
  @moduledoc "Board-wide settings: one row per key, blank clears."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Settings

  test "get is nil for an unknown key" do
    assert Settings.get("never_set") == nil
  end

  test "put stores and get reads the value" do
    :ok = Settings.put("elevenlabs_voice_id", "abc-voice")

    assert Settings.get("elevenlabs_voice_id") == "abc-voice"
  end

  test "put overwrites the previous value" do
    :ok = Settings.put("elevenlabs_voice_id", "first")
    :ok = Settings.put("elevenlabs_voice_id", "second")

    assert Settings.get("elevenlabs_voice_id") == "second"
  end

  test "a blank value clears the setting" do
    :ok = Settings.put("elevenlabs_voice_id", "abc-voice")
    :ok = Settings.put("elevenlabs_voice_id", "")

    assert Settings.get("elevenlabs_voice_id") == nil
  end

  test "nil clears the setting too" do
    :ok = Settings.put("elevenlabs_voice_id", "abc-voice")
    :ok = Settings.put("elevenlabs_voice_id", nil)

    assert Settings.get("elevenlabs_voice_id") == nil
  end
end
