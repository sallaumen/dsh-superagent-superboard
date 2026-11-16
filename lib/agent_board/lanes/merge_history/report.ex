defmodule AgentBoard.Lanes.MergeHistory.Report do
  @moduledoc "The board's weekly merge log: chronological day summaries and newest-first groups of visible PRs."

  alias AgentBoard.Lanes.MergeHistory.{Calendar, Item}
  alias AgentBoard.Usage.TaskCosts

  @doc "Assemble a calendar and its observed CI and costs into the public merge log."
  @spec build(Calendar.t(), map(), %{optional(integer()) => [TaskCosts.entry()]}) :: map()
  def build(calendar, local_ci, costs) do
    days = Enum.map(calendar.days, & &1.summary)

    entry = fn pull ->
      Item.build(pull, calendar.offset, local_ci[pull.number], costs[pull.number])
    end

    groups =
      calendar.days
      |> Enum.reverse()
      |> Enum.reject(&(&1.summary.n == 0))
      |> Enum.map(fn %{summary: day, page: page} ->
        %{
          date: day.date,
          label: day.label,
          n: day.n,
          more: page.more,
          more_wide: page.more_wide,
          items: Enum.map(page.items, entry),
          extra: Enum.map(page.extra, entry)
        }
      end)

    %{
      days: days,
      groups: groups,
      total: Enum.sum(Enum.map(days, & &1.n)),
      issues: calendar.issues
    }
  end
end
