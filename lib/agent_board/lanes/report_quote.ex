defmodule AgentBoard.Lanes.ReportQuote do
  @moduledoc "The observed words an attention item can quote, without inventing a reason."

  alias AgentBoard.Workpad

  @doc "Prefer the recorded question; only a summary containing a question can stand in."
  @spec question(String.t() | nil, String.t() | nil) :: String.t() | nil
  def question(nil, summary) do
    if Workpad.question?(summary), do: excerpt(summary)
  end

  def question(section, _summary), do: excerpt(section)

  @doc "Prefer the recorded blockage, otherwise quote a nonempty report summary."
  @spec blockage(String.t() | nil, String.t() | nil) :: String.t() | nil
  def blockage(nil, report), do: summary(report)
  def blockage(section, _summary), do: excerpt(section)

  @doc "The first line of a nonempty report summary, trimmed to at most 160 characters."
  @spec summary(String.t() | nil) :: String.t() | nil
  def summary(report) when is_binary(report) and report != "", do: excerpt(report)
  def summary(_report), do: nil

  defp excerpt(text) do
    text
    |> String.split("\n", parts: 2)
    |> hd()
    |> String.trim()
    |> String.slice(0, 160)
  end
end
