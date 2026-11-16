defmodule AgentBoard.Lanes.ReportQuoteTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.ReportQuote

  test "a recorded question wins without punctuation; a fallback must actually ask a question" do
    assert ReportQuote.question(" Which release to use ", "Ship today?") == "Which release to use"
    assert ReportQuote.question(nil, "Ship today?") == "Ship today?"
    assert ReportQuote.question(nil, "Waiting for an answer") == nil
    assert ReportQuote.question(nil, nil) == nil
  end

  test "a recorded blockage wins; absent a section, a report can explain it without a question" do
    assert ReportQuote.blockage("Missing key", "Old reason") == "Missing key"
    assert ReportQuote.blockage(nil, "Missing key") == "Missing key"
    assert ReportQuote.blockage(nil, "") == nil
  end

  test "a quote uses the trimmed first line, capped at 160 characters" do
    assert ReportQuote.summary("  Report line  \nprivate notes") == "Report line"
    assert ReportQuote.summary(String.duplicate("á", 161)) == String.duplicate("á", 160)
    assert ReportQuote.summary(nil) == nil
  end
end
