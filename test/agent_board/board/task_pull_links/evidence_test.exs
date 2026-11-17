defmodule AgentBoard.Board.TaskPullLinks.EvidenceTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Board.Repository
  alias AgentBoard.Board.TaskPullLinks.Evidence

  @repo %Repository{id: 2, owner: "Fixture", name: "Board"}
  @body "https://github.com/fixture/board/pull/3"

  test "only unnamed tasks use ticket threads, taking the highest observed number in their own repo" do
    tasks = for n <- 1..4, do: %{id: n, number: n + 10, repository_id: 2}

    tickets = %{
      11 => %{"own_threads" => [15]},
      12 => %{"own_threads" => [3, 15, 8]},
      13 => %{"own_threads" => [15]}
    }

    threads = Evidence.thread_refs(tasks, tickets, %{1 => :named})
    assert threads == %{2 => [{2, 15}, {2, 8}, {2, 3}], 3 => [{2, 15}]}

    assert Evidence.thread_matches(threads, %{
             {7, 15} => :foreign,
             {2, 8} => :newer,
             {2, 3} => :older
           }) ==
             %{2 => :newer}
  end

  test "named refs keep task IDs distinct when pull numbers and even issue numbers coincide" do
    other = %Repository{id: 7, owner: "Other", name: "Board"}
    first = %{id: 10, repository_id: 2, number: 1, body: @body}
    second = %{first | id: 20, repository_id: 7}
    tasks = [first, second, %{first | id: 30, body: nil}, %{first | id: 40, repository_id: 99}]
    comments = %{20 => [%{body: "https://github.com/Other/board/pull/3"}]}

    assert Evidence.named_refs(tasks, comments, %{2 => @repo, 7 => other}) ==
             %{10 => {2, 3}, 20 => {7, 3}}
  end

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
