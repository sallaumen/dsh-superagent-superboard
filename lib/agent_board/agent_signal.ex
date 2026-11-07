defmodule AgentBoard.AgentSignal do
  @moduledoc """
  The last sign of life of a running ticket, from what the board can see.

  The runner reports rarely (one `progress` report can be the whole run), so
  the signal is the newest of the ticket's own timestamps (report, idle,
  start) and the worktree's files. It is derived on every read and written
  nowhere: a silence is an observation about the ticket, never a state of
  the task.
  """

  alias AgentBoard.{AgentWorktree, Time}

  @default_after_ms 15 * 60 * 1000

  @type source :: :report | :start | :worktree
  @type silence :: %{at: DateTime.t(), source: source(), seconds: non_neg_integer()}

  @doc "Seconds of silence before a running ticket needs the owner (`:stall_after_ms`, 15 min)."
  @spec stall_after() :: pos_integer()
  def stall_after do
    div(Application.get_env(:agent_board, :stall_after_ms, @default_after_ms), 1000)
  end

  @doc """
  The silence of each running task, by number. A task without a ticket, or
  a ticket without any timestamp, is left out: no signal is not a silence.
  """
  @spec silences([map()], %{integer() => map()}, DateTime.t()) :: %{integer() => silence()}
  def silences(tasks, tickets_by_number, now) do
    tasks
    |> Enum.flat_map(fn task ->
      case silence(Map.get(tickets_by_number, task.number), now) do
        nil -> []
        silence -> [{task.number, silence}]
      end
    end)
    |> Map.new()
  end

  @doc "When the ticket last gave a signal, where from and how long ago."
  @spec silence(map() | nil, DateTime.t()) :: silence() | nil
  def silence(nil, _now), do: nil

  def silence(ticket, now) do
    case last_signal(ticket) do
      nil -> nil
      {at, source} -> %{at: at, source: source, seconds: Time.age_seconds(at, now)}
    end
  end

  @doc "The newest signal and its source, or nil when the ticket has no timestamp at all."
  @spec last_signal(map()) :: {DateTime.t(), source()} | nil
  def last_signal(ticket) do
    [
      {ticket["report_at"], :report},
      {ticket["idle_at"], :report},
      {ticket["started_at"], :start},
      {AgentWorktree.last_activity_at(ticket), :worktree}
    ]
    |> Enum.reject(fn {at, _source} -> is_nil(at) end)
    |> Enum.max_by(fn {at, _source} -> DateTime.to_unix(at, :millisecond) end, fn -> nil end)
  end

  @doc "Whether a silence has lasted past the threshold, in seconds."
  @spec stalled?(silence() | nil, pos_integer()) :: boolean()
  def stalled?(nil, _threshold), do: false
  def stalled?(%{seconds: seconds}, threshold), do: seconds >= threshold
end
