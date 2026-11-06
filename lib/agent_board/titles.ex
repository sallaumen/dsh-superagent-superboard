defmodule AgentBoard.Titles do
  @moduledoc """
  Title similarity for the "looks like a duplicate" warning.

  It is deliberately conservative: the board only says a queued task *looks
  like* a merged pull request, never that it is one. Case, accents and
  punctuation are ignored; the words must overlap almost completely.
  """

  @threshold 0.8

  @doc "The merged pull request a queued title most likely repeats, if any."
  @spec duplicate(String.t() | nil, [map()]) :: map() | nil
  def duplicate(title, merged) when is_binary(title) do
    merged
    |> Enum.map(&{&1, score(title, &1.title)})
    |> Enum.filter(fn {_pull, score} -> score >= @threshold end)
    |> Enum.max_by(fn {_pull, score} -> score end, fn -> nil end)
    |> case do
      nil -> nil
      {pull, _score} -> pull
    end
  end

  def duplicate(_title, _merged), do: nil

  @title_max 72
  @title_min_cut 24

  @doc """
  The issue title for a free-text request: the first non-empty line, cut at
  a sentence or clause boundary when it runs long, so a paragraph pasted as
  a request does not become a title chopped mid-word.
  """
  @spec from_request(String.t() | nil) :: String.t()
  def from_request(nil), do: ""

  def from_request(text) when is_binary(text) do
    line =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.find("", &(&1 != ""))
      |> String.replace(~r/^#+\s*/, "")

    if String.length(line) <= @title_max, do: line, else: cut_title(line)
  end

  defp cut_title(line) do
    head = String.slice(line, 0, @title_max)

    [
      ~r/^(.{#{@title_min_cut},})[.!?](?=\s)/su,
      ~r/^(.{#{@title_min_cut},})[,;:](?=\s)/su,
      ~r/^(.{#{@title_min_cut},})\s/su
    ]
    |> Enum.find_value(fn regex ->
      case Regex.run(regex, head, capture: :all_but_first) do
        [prefix] -> prefix
        _ -> nil
      end
    end)
    |> case do
      nil -> head
      prefix -> prefix
    end
    |> String.trim()
    |> Kernel.<>("…")
  end

  @doc "A 0..1 score; exact after normalization is 1.0."
  @spec score(String.t() | nil, String.t() | nil) :: float()
  def score(a, b) do
    left = tokens(a)
    right = tokens(b)

    cond do
      MapSet.size(left) == 0 or MapSet.size(right) == 0 -> 0.0
      left == right -> 1.0
      true -> jaccard(left, right)
    end
  end

  defp jaccard(left, right) do
    intersection = MapSet.intersection(left, right) |> MapSet.size()
    union = MapSet.union(left, right) |> MapSet.size()
    if union == 0, do: 0.0, else: intersection / union
  end

  defp tokens(nil), do: MapSet.new()

  defp tokens(title) do
    title
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.split(" ", trim: true)
    |> MapSet.new()
  end
end
