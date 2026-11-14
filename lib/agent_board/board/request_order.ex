defmodule AgentBoard.Board.RequestOrder do
  @moduledoc "Orders a batch for creation while retaining the positions used for its receipts."

  @doc "Free requests go first; if none is free, open the first member of a cycle."
  @spec for_creation([map()]) :: [{map(), non_neg_integer()}]
  def for_creation(requests), do: requests |> Enum.with_index() |> dependency_order()

  defp dependency_order([]), do: []

  defp dependency_order([first | _] = pending) do
    waiting = MapSet.new(pending, fn {request, _position} -> request.key end)

    next =
      Enum.find(pending, fn {request, _position} ->
        not Enum.any?(depends_on(request), &MapSet.member?(waiting, &1))
      end) || Enum.find(pending, first, &in_cycle?(&1, pending))

    [next | dependency_order(List.delete(pending, next))]
  end

  # With nothing free, only a task of the cycle may open early: one that merely
  # waits for the cycle would lose the number it could have named.
  defp in_cycle?({request, _position}, pending) do
    by_key = Map.new(pending, fn {other, _position} -> {other.key, other} end)
    reaches?(depends_on(request), request.key, by_key, MapSet.new())
  end

  defp reaches?(keys, target, by_key, seen) do
    Enum.any?(keys, fn key ->
      key == target or
        (not MapSet.member?(seen, key) and is_map_key(by_key, key) and
           reaches?(depends_on(by_key[key]), target, by_key, MapSet.put(seen, key)))
    end)
  end

  defp depends_on(request), do: Map.get(request, :depends_on, [])
end
