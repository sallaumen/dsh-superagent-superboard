defmodule AgentBoard.Board.RequestBatch do
  @moduledoc """
  A batch in the owner's order. On a retry, successful requests carry their
  original task as a receipt; only the others are sent for creation.
  """

  alias AgentBoard.Board.Task

  @doc "The requests still to send, in their original order."
  def pending(requests), do: Enum.reject(requests, &match?(%{receipt: %Task{}}, &1))

  @doc "Issue numbers already known when resolving the pending requests' dependencies."
  def confirmed_numbers(requests) do
    for %{key: key, receipt: %Task{number: number}} <- requests, into: %{}, do: {key, number}
  end

  @doc "Keep successes on the original requests, before files and links were added."
  def for_retry(requests, results) do
    Enum.zip_with(requests, results, fn
      request, {_sent, {:ok, task, _outcome}} -> Map.put(request, :receipt, task)
      request, {_sent, {:error, _reason}} -> request
    end)
  end

  @doc "Put the pending results back among prior receipts, in the owner's order."
  def merge_results(requests, pending_results) do
    {results, []} =
      Enum.map_reduce(requests, pending_results, fn
        %{receipt: %Task{} = task} = request, rest -> {{request, {:ok, task, :existing}}, rest}
        _request, [result | rest] -> {result, rest}
      end)

    results
  end
end
