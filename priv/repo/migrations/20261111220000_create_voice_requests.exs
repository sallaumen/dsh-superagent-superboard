defmodule AgentBoard.Repo.Migrations.CreateVoiceRequests do
  @moduledoc """
  One row per ElevenLabs request, beside the daily totals of
  `eleven_labs_usage`: a speech paid or served from the cache, a
  transcription, or a refusal and its reason. It holds counts only, never the
  text or the audio. `AgentBoard.ElevenLabs.Usage` writes it.
  """
  use Ecto.Migration

  def change do
    create table(:voice_requests) do
      add :kind, :string, null: false
      add :outcome, :string, null: false
      add :characters, :integer, null: false, default: 0
      add :seconds, :float, null: false, default: 0.0
      add :reason, :string
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:voice_requests, [:inserted_at])
  end
end
