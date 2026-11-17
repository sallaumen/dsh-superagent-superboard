defmodule AgentBoard.Lanes.Attention.Question do
  @moduledoc "The question evidence needed by visible attention cards."

  @doc "Select visible question issue numbers, retaining their order and occurrences."
  @spec report_numbers([map()]) :: [integer()]
  def report_numbers(visible) do
    for %{kind: :question, task: %{number: number}} <- visible,
        is_integer(number),
        do: number
  end
end
