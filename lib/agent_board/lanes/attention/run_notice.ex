defmodule AgentBoard.Lanes.Attention.RunNotice do
  @moduledoc "The evidence a running task can show on its attention card."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.AgentSignal
  alias AgentBoard.Lanes.RunTiming
  alias AgentBoard.Time

  # The item says what the board saw last and when; it never says the agent
  # died. A long model turn with no file change is a silence too.
  @doc "Describe when and where the last signal was observed."
  @spec stalled(AgentSignal.silence(), integer()) :: String.t()
  def stalled(silence, offset) do
    since = Time.local_time(silence.at, offset)

    gettext("**Last signal %{ago}.**", ago: Time.ago(silence.seconds)) <>
      " " <> silence_source(silence.source, since)
  end

  # A heads-up, not a verdict: how long, the limit that made it one, and the
  # last signal when the board has one. It never says the agent is stuck.
  @doc "Explain the elapsed run and its size limit, adding a last signal only when observed."
  @spec slow(map(), %{seconds: non_neg_integer()} | nil, DateTime.t(), integer()) :: String.t()
  def slow(task, silence, now, offset) do
    %{since: since, elapsed_seconds: elapsed, limit_minutes: limit} =
      RunTiming.slow_details(task, now)

    [
      gettext("**Working since %{time} (%{ago}).**",
        time: Time.local_time(since, offset),
        ago: Time.ago(elapsed)
      ),
      slow_limit(task.size, limit),
      case silence do
        %{seconds: seconds} -> gettext("Last signal %{ago}.", ago: Time.ago(seconds))
        nil -> nil
      end
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp silence_source(:report, since),
    do:
      gettext("The agent's last report was at %{time}; no signal in the worktree since then.",
        time: since
      )

  defp silence_source(:answer, since),
    do: gettext("The agent read your answer at %{time}; no signal since then.", time: since)

  defp silence_source(:worktree, since),
    do:
      gettext("The last change in the worktree was at %{time}; no report after it.", time: since)

  defp silence_source(:start, since),
    do:
      gettext(
        "It started at %{time} and has given no signal since: no report and no change in the worktree.",
        time: since
      )

  defp slow_limit("S", limit),
    do: gettext("A small task is flagged after %{count} min.", count: limit)

  defp slow_limit("M", limit),
    do: gettext("A medium task is flagged after %{count} min.", count: limit)

  defp slow_limit("L", limit),
    do: gettext("A large task is flagged after %{count} min.", count: limit)

  defp slow_limit(_size, limit),
    do: gettext("A task without a size is flagged after %{count} min.", count: limit)
end
