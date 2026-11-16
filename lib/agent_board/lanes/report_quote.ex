defmodule AgentBoard.Lanes.ReportQuote do
  @moduledoc "The observed words an attention item can quote, without inventing a reason."

  alias AgentBoard.Workpad

  @doc "Prefer the recorded question; only a summary containing a question can stand in."
  @spec question(String.t() | nil, String.t() | nil) :: String.t() | nil
  def question(section, report) do
    summary(section) || question_from_report(report)
  end

  defp question_from_report(report) do
    line = first_line(report)
    if Workpad.question?(line), do: String.slice(line, 0, 160)
  end

  @doc "Prefer the recorded blockage, otherwise quote a nonempty report summary."
  @spec blockage(String.t() | nil, String.t() | nil) :: String.t() | nil
  def blockage(section, report), do: summary(section) || summary(report)

  @doc "The first line of a report, trimmed to 160 characters, or nil if that line is blank."
  @spec summary(String.t() | nil) :: String.t() | nil
  def summary(report) do
    if line = first_line(report), do: String.slice(line, 0, 160)
  end

  defp first_line(report) when is_binary(report) do
    case report |> String.split("\n", parts: 2) |> hd() |> String.trim() do
      "" -> nil
      line -> line
    end
  end

  defp first_line(_report), do: nil
end
