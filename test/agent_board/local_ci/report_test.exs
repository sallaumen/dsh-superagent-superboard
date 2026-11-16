defmodule AgentBoard.LocalCI.ReportTest do
  use ExUnit.Case, async: true

  alias AgentBoard.LocalCI
  alias AgentBoard.LocalCI.Report

  test "only precommit sentences provide evidence, and explicit failure wins" do
    assert Report.gate("Remote CI passed. mix precommit scheduled.") == nil

    assert Report.gate("Remote failed. mix precommit passed with no failing tests.") == %{
             state: :pass,
             detail: "mix precommit passed with no failing tests."
           }

    assert Report.gate("mix precommit  passed. A later mix precommit failed.") == %{
             state: :fail,
             detail: "mix precommit passed."
           }
  end

  test "the evidence read by the board still limits the displayed excerpt to 220 characters" do
    summary = "PR #21 mix precommit passou " <> String.duplicate("á", 230)

    ticket = %{
      "channel_urls" => ["https://github.com/fixture/board/issues/1"],
      "reports" => [%{"summary" => summary}]
    }

    %{21 => result} = LocalCI.by_pr(%{owner: "fixture", name: "board"}, [ticket])
    assert result.state == :pass
    assert result.detail == String.slice(summary, 0, 220)
  end
end
