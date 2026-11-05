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
