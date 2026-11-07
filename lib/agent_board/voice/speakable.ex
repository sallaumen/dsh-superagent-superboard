defmodule AgentBoard.Voice.Speakable do
  @moduledoc """
  A text as it should be read out loud.

  The model and the board write for the screen: markdown, `#42`, links and
  `owner/repo` slugs. A voice reads those literally ("cerquilha quarenta e
  dois", "sallaumen barra arena hífen rogue"). This module rewrites only what
  a listener would stumble on and leaves the words alone. A hyphen between
  letters becomes a space ("arena-rogue", and "bem-vindo" reads the same).
  """

  # owner/repo: both sides at least three characters of slug alphabet, so a
  # "e/ou" or "km/h" in a sentence is left as it is.
  @slug ~r/\b[A-Za-z0-9_.-]{3,}\/([A-Za-z0-9_.-]{3,})\b/u

  @doc "The speakable form of a text."
  @spec clean(String.t()) :: String.t()
  def clean(text) when is_binary(text) do
    text
    |> String.replace(~r/\[([^\]]+)\]\([^)]+\)/u, "\\1")
    |> String.replace(~r/https?:\/\/\S+/u, "")
    |> String.replace(~r/[*_`~]{1,3}([^*_`~]+)[*_`~]{1,3}/u, "\\1")
    |> String.replace(~r/^\s*(?:[#>]+|[-*•]|\d+\.)\s+/mu, "")
    |> String.replace(@slug, fn match -> match |> String.split("/") |> List.last() |> words() end)
    |> String.replace(~r/#(\d+)/u, "\\1")
    |> String.replace(~r/(?<=\p{L})-(?=\p{L})/u, " ")
    |> String.replace(~r/[`*]/u, "")
    |> String.replace(~r/\s+([,.;:!?])/u, "\\1")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  def clean(_text), do: ""

  defp words(name), do: String.replace(name, ~r/[-_.]+/u, " ")
end
