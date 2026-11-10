defmodule AgentBoard.CommentDedupeTest do
  @moduledoc "A comment without a GitHub id must not duplicate on re-sync."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  test "the same comment is not inserted twice" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 7,
        title: "T",
        state: "queued"
      })
      |> Repo.insert!()

    comment = %{"id" => nil, "user" => %{"login" => "sallaumen"}, "body" => "same"}

    Board.upsert_comment(task, comment, "sallaumen-agent")
    Board.upsert_comment(task, comment, "sallaumen-agent")

    assert length(Board.comments(task)) == 1
  end

  test "comments stored in the same second keep the order they arrived in" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 8,
        title: "T",
        state: "queued"
      })
      |> Repo.insert!()

    comment = fn id, body ->
      %{"id" => id, "user" => %{"login" => "sallaumen"}, "body" => body}
    end

    for {id, body} <- [{1, "first"}, {2, "second"}, {3, "third"}],
        do: Board.upsert_comment(task, comment.(id, body), "sallaumen-agent")

    # an edit rewrites the row: without the id, the first comment comes back last
    Board.upsert_comment(task, comment.(1, "first, edited"), "sallaumen-agent")

    assert Enum.map(Board.comments(task), & &1.body) == ["first, edited", "second", "third"]
  end

  test "an edited comment updates the stored body" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 8,
        title: "T",
        state: "queued"
      })
      |> Repo.insert!()

    Board.upsert_comment(
      task,
      %{"id" => 5, "user" => %{"login" => "sallaumen"}, "body" => "v1"},
      "agent"
    )

    Board.upsert_comment(
      task,
      %{"id" => 5, "user" => %{"login" => "sallaumen"}, "body" => "v2"},
      "agent"
    )

    assert [comment] = Board.comments(task)
    assert comment.body == "v2"
  end
end
