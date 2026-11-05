defmodule AgentBoard.VoiceTest do
  @moduledoc "The voice: the spoken summary."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Voice

  defp board(running \\ 0, ready \\ 0, merged \\ 0, queued \\ 0) do
    %{
      running: List.duplicate(%{}, running),
      ready: List.duplicate(%{}, ready),
      merged: List.duplicate(%{}, merged),
      queued: List.duplicate(%{}, queued)
    }
  end

  defp at(hour) do
    {:ok, dt, _} =
      DateTime.from_iso8601("2026-11-04T#{String.pad_leading("#{hour}", 2, "0")}:00:00Z")

    dt
  end

  test "a calm board says so" do
    text = Voice.summary(board(), at(9))
    assert text =~ "Good morning"
    assert text =~ "calm"
  end

  test "the counts are spoken" do
    text = Voice.summary(board(1, 0, 8, 2), at(14))
    assert text =~ "Good afternoon"
    assert text =~ "1 running"
    assert text =~ "8 recent merges"
    assert text =~ "2 queued"
  end

  test "two counts join with and" do
    text = Voice.summary(board(0, 0, 1, 1), at(20))
    assert text =~ "1 recent merges and 1 queued"
  end

  test "a blocked-only board is not called calm" do
    text = Voice.summary(%{blocked: [%{}]}, at(9))
    assert text =~ "1 blocked"
    refute text =~ "calm"
  end

  test "the greeting changes with the hour" do
    assert Voice.summary(board(), at(7)) =~ "Good morning"
    assert Voice.summary(board(), at(15)) =~ "Good afternoon"
    assert Voice.summary(board(), at(22)) =~ "Good evening"
  end

  test "the task confirmation is one line" do
    assert Voice.task_summary("Add a boss", "created") == "Task 'Add a boss' is created."
  end
end
