defmodule AgentBoardWeb.VoiceMutations do
  @moduledoc "Explicit task state requests; parsing never executes an action."

  @stop ~r/\A(?:stop|parar|pare) (?:a |o |the )?(?:tarefa|task|issue) #?([1-9]\d*)\z/u
  @archive ~r/\A(?:archive|arquivar|arquive) (?:a |o |the )?(?:tarefa|task|issue) #?([1-9]\d*)\z/u

  @doc "Recognize only a numbered task command with an explicit action and noun."
  def parse(text) when is_binary(text) and byte_size(text) <= 500 do
    phrase =
      text
      |> String.trim()
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim_trailing(".")

    cond do
      match = Regex.run(@stop, phrase) -> intent(:stop, match)
      match = Regex.run(@archive, phrase) -> intent(:archive, match)
      true -> :not_mutation
    end
  end

  def parse(_text), do: :not_mutation

  defp intent(action, [_, number]) do
    case Integer.parse(number) do
      {value, ""} -> {:ok, %{action: action, number: value}}
      _ -> :not_mutation
    end
  end
end
