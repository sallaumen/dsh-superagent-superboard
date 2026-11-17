defmodule AgentBoard.Lanes.RunTiming do
  @moduledoc "Time limits for a running task, calculated from its observed timestamps."

  alias AgentBoard.Time

  # Minutes of work the owner allows a running task before being told, by
  # size (2026-11-10: small 20, large 60). A task without a size, as most
  # issues opened on GitHub are, waits as long as a large one.
  @slow_after %{"S" => 20, "M" => 40, "L" => 60}
  @slow_after_unsized 60

  @doc "Seconds of work after which a running task of this size is a heads-up."
  @spec slow_after(String.t() | nil) :: pos_integer()
  def slow_after(size), do: Map.get(@slow_after, size, @slow_after_unsized) * 60

  # The work counts from when the task last became `running`: a retry or the
  # owner's answer starts it again, and the time it waited is not work.
  @doc "Since when a running task works: time spent waiting is not work."
  @spec working_since(map()) :: DateTime.t() | nil
  def working_since(task), do: task.state_changed_at || task.started_at

  @doc "The observed start, nonnegative elapsed seconds and size allowance used by a long-run notice."
  @spec slow_details(map(), DateTime.t()) :: %{
          since: DateTime.t() | nil,
          elapsed_seconds: non_neg_integer() | nil,
          limit_minutes: pos_integer()
        }
  def slow_details(task, now) do
    since = working_since(task)

    %{
      since: since,
      elapsed_seconds: Time.age_seconds(since, now),
      limit_minutes: div(slow_after(task.size), 60)
    }
  end

  @doc "The moment a running task passes the time its size allows, or nil."
  @spec slow_at(map()) :: DateTime.t() | nil
  def slow_at(task) do
    case working_since(task) do
      %DateTime{} = since -> DateTime.add(since, slow_after(task.size), :second)
      nil -> nil
    end
  end

  @doc "Whether a running task has passed the time its size allows."
  @spec slow?(map(), DateTime.t()) :: boolean()
  def slow?(task, now) do
    case slow_at(task) do
      %DateTime{} = at -> DateTime.compare(now, at) != :lt
      nil -> false
    end
  end

  @doc "When a known signal goes quiet, or nil without a signal."
  @spec silence_at(%{at: DateTime.t()} | nil, integer()) :: DateTime.t() | nil
  def silence_at(nil, _stall_after), do: nil
  def silence_at(%{at: at}, stall_after), do: DateTime.add(at, stall_after, :second)

  @doc """
  Milliseconds until the next running task becomes a long run or goes silent, nil
  when none will. Nothing broadcasts a task that goes quiet, so the open board
  sets one timer for this moment instead of waiting for the next sync.
  """
  @spec next_attention_in([map()], map(), pos_integer(), DateTime.t()) :: pos_integer() | nil
  def next_attention_in(running, silences, stall_after, now) do
    running
    |> Enum.flat_map(fn task ->
      [slow_at(task), silence_at(silences[task.number], stall_after)]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&DateTime.diff(&1, now, :millisecond))
    |> Enum.filter(&(&1 > 0))
    |> Enum.min(fn -> nil end)
  end
end
