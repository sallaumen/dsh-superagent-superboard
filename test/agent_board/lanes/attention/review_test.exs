defmodule AgentBoard.Lanes.Attention.ReviewTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.Attention.Review

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "a linked PR supplies the subject even without a destination URL" do
    assert Review.subject(%PullRequest{number: 8, url: nil}, "Old report") == {:pull, 8}
    assert Review.subject(%PullRequest{number: 9, url: "/pull/9"}, nil) == {:pull, 9}
  end

  test "the fallback subject quotes only a trimmed and bounded first report line" do
    assert Review.subject(nil, "  Needs approval  \nFurther details") ==
             {:summary, "Needs approval"}

    assert Review.subject(nil, String.duplicate("á", 161)) ==
             {:summary, String.duplicate("á", 160)}
  end

  test "absent or blank first-line evidence leaves the subject unidentified" do
    for summary <- [nil, "", "  ", "\nLater detail"] do
      assert Review.subject(nil, summary) == :unidentified
    end
  end

  test "the PR number and link come from the pull; the review action still opens the task" do
    pull = %PullRequest{number: 8, url: "/pull/8"}
    task = %{label: "Review", task_id: 32}
    why = "**PR #8 ready for review**"

    assert Review.content(32, pull, "old report") ==
             {why, [task, %{label: "Open PR #8", url: "/pull/8"}]}

    assert Review.content(32, %{pull | url: nil}, nil) == {why, [task]}
  end

  test "an unidentified PR never gets a link; only a usable summary is quoted" do
    actions = [%{label: "Review", task_id: 32}]

    assert Review.content(32, nil, "Needs approval") ==
             {"**Ready for review**, PR not identified. The agent said: Needs approval", actions}

    assert Review.content(32, nil, "  ") ==
             {"**Ready for review**, PR not identified by the board. Open the conversation.",
              actions}
  end
end
