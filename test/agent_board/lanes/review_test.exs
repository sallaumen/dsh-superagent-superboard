defmodule AgentBoard.Lanes.ReviewTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.Review

  @sha String.duplicate("a1", 20)

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "native decisions win without reading the report or needing a head" do
    for {state, label} <- [{"approved", "approved"}, {"changes_requested", "changes requested"}] do
      pull = %{review_state: state, reported_evidence: %{"review" => :unreadable}}
      assert Review.classify(pull) == {:native, state}
      assert Review.label(pull) == label
    end
  end

  test "without a review report the native state is retained" do
    for evidence <- [nil, %{}, %{"ci" => %{}}],
        {state, label} <- [
          {"pending", "review pending"},
          {"none", "no review"},
          {nil, "no review"}
        ] do
      pull = %PullRequest{review_state: state, reported_evidence: evidence}
      assert Review.classify(pull) == {:native, state}
      assert Review.label(pull) == label
    end

    assert Review.classify(%{}) == {:native, nil}
    assert Review.label(%{}) == "no review"
  end

  test "a current report keeps its attribution, including case-insensitive SHA matching" do
    for {result, label} <- [
          {"approved", "Independent review reported"},
          {"changes_requested", "Changes requested in report"}
        ] do
      pull = pull(%{"sha" => String.upcase(@sha), "result" => result})
      assert Review.classify(pull) == {:reported, result}
      assert Review.label(pull) == label
    end
  end

  test "a report from another commit is stale even when it approved the work" do
    pull = pull(%{"sha" => String.duplicate("b2", 20), "result" => "approved"})
    assert Review.classify(pull) == {:reported, "stale"}
    assert Review.label(pull) == "Review report outdated"
  end

  test "missing commit or result evidence is incomplete, never a native approval" do
    for {report, head, state} <- [
          {%{"result" => "approved"}, @sha, "unknown"},
          {%{"sha" => @sha, "result" => "approved"}, nil, "unknown"},
          {%{"sha" => @sha}, @sha, nil},
          {%{"sha" => @sha, "result" => "unknown"}, @sha, "unknown"}
        ] do
      pull = %{pull(report) | head_sha: head}
      assert Review.classify(pull) == {:reported, state}
      assert Review.label(pull) == "Review report incomplete"
    end
  end

  defp pull(report),
    do: %PullRequest{
      review_state: "pending",
      head_sha: @sha,
      reported_evidence: %{"review" => report}
    }
end
