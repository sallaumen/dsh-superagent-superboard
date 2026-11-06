defmodule AgentBoard.Repo.Migrations.AddTaskToAiCalls do
  @moduledoc "Attribute the board's own AI call to the task it answered, when there is one."
  use Ecto.Migration

  def change do
    alter table(:ai_calls) do
      add :task_id, references(:tasks, on_delete: :nilify_all)
    end

    create index(:ai_calls, [:task_id, :inserted_at])
  end
end
