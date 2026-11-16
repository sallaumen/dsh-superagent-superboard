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
  def duplicate(title, merged) when is_binary(title),
    do: Map.get(duplicates([title], merged), title)

  def duplicate(_title, _merged), do: nil

  @doc "Best repeat for each matching queue title; normalize the merged history once for the batch."
  @spec duplicates([String.t() | nil], [map()]) :: %{optional(String.t()) => map()}
  def duplicates([], _merged), do: %{}
  def duplicates(_titles, []), do: %{}

  def duplicates(titles, merged) do
    candidates = Enum.map(merged, &{&1, tokens(&1.title)})

    for title <- Enum.uniq(titles),
        is_binary(title),
        pull = best_match(tokens(title), candidates),
        into: %{},
        do: {title, pull}
  end

  defp best_match(words, candidates) do
    {pull, _score} =
      Enum.reduce(candidates, {nil, 0.0}, fn {pull, other_words}, {_, best_score} = best ->
        score = token_score(words, other_words)
        if score >= @threshold and score > best_score, do: {pull, score}, else: best
      end)

    pull
  end

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
  def score(a, b), do: token_score(tokens(a), tokens(b))

  defp token_score(left, right) do
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
