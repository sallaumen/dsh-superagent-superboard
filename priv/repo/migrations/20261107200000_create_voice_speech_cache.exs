defmodule AgentBoard.Repo.Migrations.CreateVoiceSpeechCache do
  @moduledoc """
  The durable layer of `AgentBoard.ElevenLabs.SpeechCache`: the mp3 of a
  short text the board already paid ElevenLabs for, keyed exactly like the
  in-memory cache (a sha256 of the text and every option that shapes the
  audio). A fixed phrase is paid once, not once per restart. Bounded in rows
  and expired 30 days after its last use by the cache itself.
  """
  use Ecto.Migration

  def change do
    create table(:voice_speech_cache, primary_key: false) do
      add :key, :binary, primary_key: true
      add :audio, :binary, null: false
      add :text_length, :integer, null: false
      add :last_used_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:voice_speech_cache, [:last_used_at])
  end
end
