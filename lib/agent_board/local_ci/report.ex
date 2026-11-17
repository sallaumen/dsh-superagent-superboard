defmodule AgentBoard.LocalCI.Report do
  @moduledoc "Read explicitly reported local checks and historical precommit reports."

  alias AgentBoard.Workpad

  # Summaries can mention a remote build, a review or a plan. Only read
  # the verdict attached to a named local command; never run the command.
  @local ~r/(?:^|[\s:])(?:local CI|CI local):\s*`[^`\n]+`\s*:\s*(.*)$/iu
  @legacy ~r/\bmix precommit\b\s*:?\s*(.*)$/i

  @spec gate(String.t()) :: %{state: :pass | :fail, detail: String.t()} | nil
  def gate(summary) do
    outcomes =
      summary
      |> String.split(~r/(?<=[.!?])\s+|\n+/)
      |> Enum.flat_map(&evidence/1)

    Enum.find(outcomes, &(&1.state == :fail)) || List.first(outcomes)
  end

  defp evidence(sentence) do
    with [_, result] <- Regex.run(@local, sentence) || Regex.run(@legacy, sentence),
         verdict when is_boolean(verdict) <- Workpad.reported_outcome(result) do
      [
        %{
          state: if(verdict, do: :pass, else: :fail),
          detail: String.trim(String.replace(sentence, ~r/\s+/, " "))
        }
      ]
    else
      _ -> []
    end
  end
end
