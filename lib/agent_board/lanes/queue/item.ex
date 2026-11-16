defmodule AgentBoard.Lanes.Queue.Item do
  @moduledoc "A queue card assembled from an observed task and the evidence for its repository."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.Queue
  alias AgentBoard.Time

  @doc "Describe one row, preserving the split and repeat flags even when the subtitle describes a wait."
  @spec build(map(), map(), map()) :: map()
  def build(candidate, waits, calls) do
    row = candidate.row
    detail = Queue.Detail.describe(row, candidate.relationship, Map.get(waits, row.id, []), calls)

    %{
      key: "task-#{row.id}",
      id: row.id,
      number: row.number,
      title: row.title,
      age_seconds: Time.age_seconds(row.inserted_at, calls.now),
      is_new: candidate.is_new,
      sub: detail.sub,
      stuck: detail.stuck,
      split: not is_nil(candidate.relationship),
      note:
        candidate.repeat &&
          gettext("Looks like a repeat of #%{number}, already merged",
            number: candidate.repeat.number
          )
    }
  end
end
