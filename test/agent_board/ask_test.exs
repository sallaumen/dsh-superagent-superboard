defmodule AgentBoard.AskTest do
  @moduledoc "The Ask flow: optimistic comment, reconciled with GitHub."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @stub AgentBoard.AskTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 42,
        title: "Talk",
        state: "queued"
      })
      |> Repo.insert!()
      |> Repo.preload(:repository)

    %{task: task}
  end

  defp client, do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub})

  test "the comment appears immediately and the id is reconciled", %{task: task} do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"id" => 999, "user" => %{"login" => "sallaumen"}})
    end)

    assert {:ok, comment} = Board.ask(task, "hello", client())
    assert comment.github_id == 999
    assert comment.author == "sallaumen"

    assert [only] = Board.comments(task)
    assert only.body =~ "hello"
  end

  test "ask reloads the repository when the task has none preloaded", %{task: task} do
    bare = Repo.get(Task, task.id)

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"id" => 99, "user" => %{"login" => "sallaumen"}})
    end)

    assert {:ok, _} = Board.ask(bare, "hi", client())
  end

  test "a failed request removes the placeholder", %{task: task} do
    Req.Test.stub(@stub, fn conn ->
      Plug.Conn.send_resp(conn, 500, "boom")
    end)

    assert {:error, %RuntimeError{}} = Board.ask(task, "hello", client())
    assert Board.comments(task) == []
  end
end
