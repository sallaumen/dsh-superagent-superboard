defmodule AgentBoard.Lanes.Queue do
  @moduledoc "Rules for the queue, applied to the rows the board observed."

  alias AgentBoard.Lanes.CallStatus
  alias AgentBoard.{Time, Titles}

  @compact_limit 8

  @doc "Collect origin and blocker task IDs once, preserving their first occurrence."
  @spec related_ids([map()]) :: [integer()]
  def related_ids(rows) do
    rows
    |> Enum.flat_map(&[&1.origin_task_id, &1.blocker_for_task_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc "Number of rows on the compact queue page."
  @spec compact_limit() :: pos_integer()
  def compact_limit, do: @compact_limit

  @doc "Offer filters only when the full queue exceeds the compact page, in display order with full counts."
  @spec filter_options(map()) :: [{:all | :new | :split | :dupes, non_neg_integer()}]
  def filter_options(%{all: all}) when all <= @compact_limit, do: []

  def filter_options(counts),
    do: [all: counts.all, new: counts.new, split: counts.split, dupes: counts.dupes]

  @doc "A task names what it unblocks before the task it was split from."
  @spec relationship(integer() | nil, integer() | nil) ::
          {:unblocks | :split_from, integer()} | nil
  def relationship(blocked_number, _origin) when is_integer(blocked_number),
    do: {:unblocks, blocked_number}

  def relationship(nil, origin) when is_integer(origin), do: {:split_from, origin}
  def relationship(_blocked_number, _origin), do: nil

  @doc "Select visible rows using only the facts needed to count, filter and order the queue."
  @spec select(map(), DateTime.t() | nil, atom(), integer()) :: map()
  def select(observed, last_visit, filter, limit) do
    repeats = Titles.duplicates(Enum.map(observed.rows, & &1.title), observed.merged)

    candidates =
      Enum.map(observed.rows, fn row ->
        %{
          row: row,
          relationship:
            relationship(
              observed.related_numbers[row.blocker_for_task_id],
              observed.related_numbers[row.origin_task_id]
            ),
          repeat: repeats[row.title],
          is_new: Time.new_since?(row.inserted_at, last_visit)
        }
      end)

    page = page(candidates, filter, limit)
    Map.put(page, :filters, filter_options(page.counts))
  end

  @doc "Visible held tasks whose cards can name unresolved blockers; call problems take precedence."
  @spec waiting_ids(map(), map()) :: [integer()]
  def waiting_ids(page, calls) do
    for %{row: row} <- page.items,
        CallStatus.dependency_wait?(row.held, CallStatus.problem(row, calls)),
        do: row.id
  end

  @doc "Page queue candidates or built cards: count the full queue, then filter in order before limiting."
  @spec page([map()], atom(), integer()) :: map()
  def page(items, filter, limit) do
    counts = %{
      all: length(items),
      new: Enum.count(items, &matches?(&1, :new)),
      split: Enum.count(items, &matches?(&1, :split)),
      dupes: Enum.count(items, &matches?(&1, :dupes))
    }

    filtered = if filter == :all, do: items, else: Enum.filter(items, &matches?(&1, filter))
    total = length(filtered)

    %{
      items: Enum.take(filtered, limit),
      total: total,
      hidden: max(total - limit, 0),
      counts: counts,
      filter: filter,
      limit: limit
    }
  end

  defp matches?(item, :new), do: item.is_new
  defp matches?(%{relationship: link}, :split), do: not is_nil(link)
  defp matches?(card, :split), do: card.split
  defp matches?(%{repeat: repeat}, :dupes), do: not is_nil(repeat)
  defp matches?(card, :dupes), do: not is_nil(card.note)
  defp matches?(_item, _all), do: true
end
