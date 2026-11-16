defmodule AgentBoard.Lanes.Attention.RunNoticeTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Attention.RunNotice

  @at ~U[2026-11-07 12:00:00Z]

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "the silence identifies the observed source in the local time of its reader" do
    sources = [
      report: "The agent's last report was at 09:00; no signal in the worktree since then.",
      answer: "The agent read your answer at 09:00; no signal since then.",
      worktree: "The last change in the worktree was at 09:00; no report after it.",
      start:
        "It started at 09:00 and has given no signal since: no report and no change in the worktree."
    ]

    for {source, expected} <- sources do
      assert RunNotice.stalled(%{at: @at, seconds: 900, source: source}, 180) ==
               "**Last signal 15 min ago.** " <> expected
    end
  end

  test "a long run names its size threshold and only includes a signal when supplied" do
    task = %{size: "S", state_changed_at: @at}
    now = DateTime.add(@at, 1200)
    base = "**Working since 09:00 (20 min ago).** A small task is flagged after 20 min."
    assert RunNotice.slow(task, nil, now, 180) == base
    assert RunNotice.slow(task, %{seconds: 120}, now, 180) == base <> " Last signal 2 min ago."

    assert RunNotice.slow(%{task | size: nil}, nil, DateTime.add(@at, 3600), 180) =~
             "A task without a size is flagged after 60 min."
  end
end
