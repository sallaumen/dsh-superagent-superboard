defmodule AgentBoard.Lanes.MergeHistory.Calendar do
  @moduledoc "The seven local days of the merge log, with complete counts and a bounded page per day."

  alias AgentBoard.Lanes.MergeHistory
  alias AgentBoard.Time

  @type t :: %{
          days: [%{summary: map(), page: map()}],
          issues: non_neg_integer(),
          offset: integer()
        }

  @doc "Keep empty dates and count every in-window issue once, preserving the supplied PR order within each day."
  @spec build([map()], MergeHistory.window(), map()) :: t()
  def build(pulls, window, local_ci) do
    by_date = Enum.group_by(pulls, &Time.local_date(&1.merged_at, window.offset))
    buckets = Enum.map(window.dates, &{&1, Map.get(by_date, &1, [])})

    days =
      for {date, rows} <- buckets do
        summary =
          rows
          |> MergeHistory.day_totals(local_ci)
          |> Map.merge(%{
            date: date,
            label: Time.day_label(date, window.today),
            today: date == window.today
          })

        %{summary: summary, page: MergeHistory.day_page(rows)}
      end

    issues = buckets |> Enum.flat_map(fn {_date, rows} -> rows end) |> MergeHistory.delivered()
    %{days: days, issues: issues, offset: window.offset}
  end
end
