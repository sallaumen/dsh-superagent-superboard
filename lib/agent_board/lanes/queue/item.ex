defmodule AgentBoard.Lanes.Queue.Item do
  @moduledoc "A queue card assembled from an observed task and the evidence for its repository."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.Queue
  alias AgentBoard.{Time, Titles}

  @doc "Describe one row, preserving the split and repeat flags even when the subtitle describes a wait."
  @spec build(map(), map(), map(), DateTime.t() | nil) :: map()
  def build(row, observed, calls, last_visit) do
    relationship =
      Queue.relationship(
        observed.related_numbers[row.blocker_for_task_id],
        observed.related_numbers[row.origin_task_id]
      )

    detail = Queue.Detail.describe(row, relationship, Map.get(observed.waits, row.id, []), calls)
    duplicate = Titles.duplicate(row.title, observed.merged)

    %{
      key: "task-#{row.id}",
      id: row.id,
      number: row.number,
      title: row.title,
      age_seconds: Time.age_seconds(row.inserted_at, calls.now),
      is_new: Time.new_since?(row.inserted_at, last_visit),
      sub: detail.sub,
      stuck: detail.stuck,
      split: not is_nil(relationship),
      note:
        duplicate &&
          gettext("Looks like a repeat of #%{number}, already merged", number: duplicate.number)
    }
  end
end
