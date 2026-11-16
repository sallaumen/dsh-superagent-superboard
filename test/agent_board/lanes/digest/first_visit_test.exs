defmodule AgentBoard.Lanes.Digest.FirstVisitTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes
  @now ~U[2026-11-16 12:00:00Z]

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  # First visits need only the board snapshot, never a repository.
  defp digest(board, opts), do: Lanes.digest(nil, board, [now: @now] ++ opts)

  test "an empty board has no sentence, including during a sync interruption" do
    assert digest(%{}, []) == nil
    assert digest(%{}, frozen: true) == nil
  end

  test "activity uses full lane counts, reading order and the owner's role" do
    board = %{task_counts: %{running: 2, question: 1, ready: 1, blocked: 1}}

    assert digest(board, []) == %{
             prefix: "First visit: ",
             now: @now,
             suffix: ".",
             segments: [
               %{text: "2 running", role: :agent},
               %{text: ", ", role: :plain},
               %{text: "2 waiting for you", role: :you},
               %{text: " and ", role: :plain},
               %{text: "1 blocked", role: :halt}
             ]
           }
  end

  test "an interrupted sync marks where knowledge ends, even without a completed sync" do
    board = %{task_counts: %{queued: 1}}
    known = digest(board, frozen_at: @now, tz_offset: 180)
    assert known.prefix == "Until 09:00: "
    assert known.segments == [%{text: "1 in the queue", role: :agent}]
    assert known.suffix == " After that, we do not know."
    unknown = digest(board, frozen: true)
    assert unknown == %{known | prefix: "Without a completed sync: "}
  end
end
