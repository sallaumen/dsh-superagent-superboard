defmodule AgentBoard.Voice do
  @moduledoc """
  The voice: a short, spoken status of the board.

  The text is generated here, in plain functions, so it can be tested without a
  browser. The browser speaks it with the Web Speech API; the server never needs
  a TTS engine.
  """

  @doc "A spoken status: what is running, ready, queued and merged."
  def summary(board, now \\ DateTime.utc_now()) do
    parts =
      [
        {count(board, :running), "running"},
        {count(board, :ready), "ready for review"},
        {count(board, :merged), "merged"},
        {count(board, :queued), "queued"}
      ]
      |> Enum.reject(fn {n, _} -> n == 0 end)
      |> Enum.map(fn {n, label} -> "#{n} #{label}" end)

    case parts do
      [] ->
        "#{greeting(now)}. The board is calm: nothing is running and nothing is waiting."

      [one] ->
        "#{greeting(now)}. On the board: #{one}."

      many ->
        "#{greeting(now)}. On the board: #{Enum.join(Enum.drop(many, -1), ", ")} and #{List.last(many)}."
    end
  end

  @doc "The one-line confirmation spoken when a task is created or acted on."
  def task_summary(title, state), do: "Task '#{title}' is #{state}."

  @doc "The greeting for the hour of the day."
  def greeting(now) do
    case now.hour do
      h when h < 12 -> "Good morning"
      h when h < 18 -> "Good afternoon"
      _ -> "Good evening"
    end
  end

  defp count(board, key), do: length(Map.get(board, key) || [])
end
