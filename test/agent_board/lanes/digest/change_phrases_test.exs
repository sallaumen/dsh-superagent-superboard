defmodule AgentBoard.Lanes.Digest.ChangePhrasesTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Digest.ChangePhrases

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "review and task links belong to their own words, never to separators or counts" do
    facts = [reviews: 2, running: {:task, 91, 7}, blocked: 3]

    assert ChangePhrases.segments(facts, %{url: "/pull/12"}) == [
             %{text: "it opened 2 PRs for review", role: :you, url: "/pull/12"},
             %{text: ", ", role: :plain},
             %{text: "it is working on #7", role: :agent, task_id: 91},
             %{text: " and ", role: :plain},
             %{text: "3 are still blocked", role: :halt}
           ]
  end

  test "a review without a target keeps its wording; no facts yield no segments" do
    assert ChangePhrases.segments([reviews: 1], nil) == [
             %{text: "it opened 1 PR for review", role: :you, url: nil}
           ]

    assert ChangePhrases.segments([], nil) == []
  end
end
