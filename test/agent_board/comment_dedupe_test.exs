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
end
