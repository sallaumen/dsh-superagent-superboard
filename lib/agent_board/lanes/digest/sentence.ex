defmodule AgentBoard.Lanes.Digest.Sentence do
  @moduledoc "Join digest segments without losing links or the role of the words between them."

  @doc "Use commas between earlier segments and the supplied conjunction before the last."
  @spec join([map()], String.t()) :: [map()]
  def join([], _conjunction), do: []
  def join([only], _conjunction), do: [only]

  def join(segments, conjunction) do
    {leading, [last]} = Enum.split(segments, -1)

    Enum.intersperse(leading, %{text: ", ", role: :plain}) ++
      [%{text: " " <> conjunction <> " ", role: :plain}, last]
  end
end
