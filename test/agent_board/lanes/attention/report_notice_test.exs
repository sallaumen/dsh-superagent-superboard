defmodule AgentBoard.Lanes.Attention.ReportNoticeTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Attention.ReportNotice

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "a recorded question wins and a report without a quotable question stays neutral" do
    assert ReportNotice.question("Which version", "Use v1?") ==
             "**The agent asked:** Which version"

    assert ReportNotice.question(nil, "Use v1?") == "**The agent asked:** Use v1?"

    assert ReportNotice.question(nil, "Waiting") ==
             "**The agent is waiting for your answer.** Open the conversation and reply."
  end

  test "the blockage can quote a report; a missing explanation never becomes a reason" do
    assert ReportNotice.blockage("Build failed", "Old status") == "**Blocked:** Build failed"
    assert ReportNotice.blockage(nil, "Missing key") == "**Blocked:** Missing key"

    assert ReportNotice.blockage(nil, " ") ==
             "**Blocked**, with no reason in the agent's report. Open the details."
  end
end
