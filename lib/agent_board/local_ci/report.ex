defmodule AgentBoard.LocalCI.Report do
  @moduledoc "Evidence of a precommit run in an executor's report text."

  alias AgentBoard.Workpad

  @pass ~r/\b(passed|passes|passou|passaram|green|verde|0 failures|0 falhas|0 issues)\b/i
  @fail ~r/\bn[ãa]o\s+pass(?:ou|aram)\b|\bdid(?:\s+not|n['’]t)\s+pass\b|\b(failed|failing|falhou|falharam)\b|[1-9]\d*\s+(failures|falhas|issues)/iu

  @doc "Read only precommit sentences. A failure wins; the first matching sentence supplies the excerpt."
  @spec gate(String.t()) :: %{state: :pass | :fail, detail: String.t()} | nil
  def gate(summary) do
    sentences =
      summary
      |> String.split(~r/(?<=[.!?])\s+|\n+/)
      |> Enum.filter(&(&1 =~ ~r/mix precommit/i))

    case outcome(sentences) do
      nil ->
        nil

      state ->
        %{
          state: state,
          detail: sentences |> hd() |> String.replace(~r/\s+/, " ") |> String.trim()
        }
    end
  end

  defp outcome(sentences) do
    cond do
      Enum.any?(sentences, &(Workpad.without_negated_failures(&1) =~ @fail)) -> :fail
      Enum.any?(sentences, &(&1 =~ @pass)) -> :pass
      true -> nil
    end
  end
end
