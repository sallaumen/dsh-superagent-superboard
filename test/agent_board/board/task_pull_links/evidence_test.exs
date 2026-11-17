defmodule AgentBoard.Board.TaskPullLinks.EvidenceTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Board.Repository
  alias AgentBoard.Board.TaskPullLinks.Evidence

  @repo %Repository{id: 2, owner: "Fixture", name: "Board"}
  @body "https://github.com/fixture/board/pull/3"

  test "newest local comment wins; skip newer foreign links, invalid numbers and unlinked text" do
    comments = [
      %{body: "https://github.com/fixture/board/pull/4"},
      %{
        body:
          "https://github.com/fixture/board/pull/0 then https://github.com/FIXTURE/BOARD/pull/5"
      },
      %{body: "https://github.com/other/board/pull/6"}
    ]

    assert Evidence.named_number(@body, comments, @repo) == 5
    assert Evidence.named_number(@body, [List.last(comments)], @repo) == 3
    assert Evidence.named_number(nil, [%{body: "PR #8 ready"}], @repo) == nil
    assert Evidence.named_number(@body, comments, nil) == nil
  end
end
