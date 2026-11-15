defmodule AgentBoard.Lanes.RunTiming do
  @moduledoc "Time limits for a running task, calculated from its observed timestamps."

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
end
