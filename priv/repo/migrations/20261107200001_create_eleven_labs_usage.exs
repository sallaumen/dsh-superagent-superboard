defmodule AgentBoard.Repo.Migrations.CreateElevenLabsUsage do
  @moduledoc """
  The ElevenLabs ledger, one row per UTC day: TTS characters paid (from the
  `x-character-count` header, or the text length when it is absent), TTS
  requests and cache hits (which cost nothing), and STT audio seconds (from
  the transcript's `audio_duration_secs`). `AgentBoard.ElevenLabs.Usage`
  adds to it atomically.
  """
  use Ecto.Migration

  def change do
    create table(:eleven_labs_usage, primary_key: false) do
      add :day, :date, primary_key: true
      add :tts_characters, :integer, null: false, default: 0
      add :tts_requests, :integer, null: false, default: 0
      add :cache_hits, :integer, null: false, default: 0
      add :stt_seconds, :float, null: false, default: 0.0
      add :stt_requests, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end
  end
end
