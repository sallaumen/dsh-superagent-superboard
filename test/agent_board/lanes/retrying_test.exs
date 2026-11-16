defmodule AgentBoard.Lanes.RetryingTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.Task
  alias AgentBoard.Lanes

  @at ~U[2026-11-07 17:10:00Z]

  test "retry rows need no review PR lookup and distinguish an explained retry from a missing ticket" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")

    board = %{
      ready: [%Task{id: 30, repository_id: 4, number: 90}],
      retrying: [
        %Task{id: 10, number: 61, title: "Transport"},
        %Task{id: 20, number: 62, title: "Waiting"}
      ]
    }

    ticket = %{
      "id" => "t1",
      "assignments" => [
        %{
          "id" => "a1",
          "report" => "failed",
          "summary" => "LlmError: DeepSeek Messages transport failed",
          "report_at" => @at
        }
      ]
    }

    opts = [tickets_by_number: %{61 => ticket}, now: @at, tz_offset: 180]

    assert Lanes.retrying(board, opts) == [
             %{
               id: 10,
               number: 61,
               title: "Transport",
               line: "**Network failure calling the model.** Automatic retry at 14:11 (1 of 3)."
             },
             %{
               id: 20,
               number: 62,
               title: "Waiting",
               line: "**Automatic retry.** Waiting for the agent."
             }
           ]

    assert [first, _] = Lanes.retrying(board, Keyword.put(opts, :agent, :down))
    assert first.line =~ "Automatic retry when the agent is back"
  end
end
