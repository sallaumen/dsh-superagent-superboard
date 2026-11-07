defmodule AgentBoard.AgentWorktree.Cache do
  @moduledoc """
  The last observation of each worktree, kept in memory for a few seconds.

  Every board render asked `git` about every running worktree, and a render
  happens per LiveView, per broadcast and per page probe: the same answer
  was recomputed many times a second. An entry here is that answer, keyed by
  the worktree's directory and reused while it is younger than the TTL
  (`:worktree_ttl_ms`, the poll interval by default; 0 disables the cache).
  A restart empties it; nothing is written anywhere else.
  """
  use GenServer

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc """
  The value kept for `key` while it is younger than `ttl_ms`; otherwise
  `read` runs, and its result is kept and returned. Expired entries are
  dropped on the way, so the table holds only the worktrees read recently.
  """
  @spec fetch(term(), non_neg_integer(), (-> value)) :: value when value: term()
  def fetch(key, ttl_ms, read) when is_function(read, 0) do
    if ttl_ms > 0 and :ets.whereis(@table) != :undefined do
      now = System.monotonic_time(:millisecond)

      case :ets.lookup(@table, key) do
        [{^key, value, at}] when now - at < ttl_ms -> value
        _ -> store(key, read.(), now, ttl_ms)
      end
    else
      read.()
    end
  end

  defp store(key, value, now, ttl_ms) do
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now - ttl_ms}], [true]}])
    :ets.insert(@table, {key, value, now})
    value
  end
end
