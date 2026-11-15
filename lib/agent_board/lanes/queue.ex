defmodule AgentBoard.Lanes.Queue do
  @moduledoc "Rules for the queue, applied to the rows the board observed."

  @doc "A task names what it unblocks before the task it was split from."
  @spec relationship(integer() | nil, integer() | nil) ::
          {:unblocks | :split_from, integer()} | nil
  def relationship(blocked_number, _origin) when is_integer(blocked_number),
    do: {:unblocks, blocked_number}

  def relationship(nil, origin) when is_integer(origin), do: {:split_from, origin}
  def relationship(_blocked_number, _origin), do: nil

  @doc "Count the full queue, then filter in the supplied order before limiting the visible rows."
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
  defp matches?(item, :split), do: item.split
  defp matches?(item, :dupes), do: not is_nil(item.note)
  defp matches?(_item, _all), do: true
end
