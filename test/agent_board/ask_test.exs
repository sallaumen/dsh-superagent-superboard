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

  test "a mirrored comment wins the race with its POST and keeps later edits", %{task: task} do
    Req.Test.stub(@stub, fn conn ->
      {:ok, json, conn} = Plug.Conn.read_body(conn)

      remote = %{
        "id" => 6_945_214_247,
        "body" => Jason.decode!(json)["body"],
        "user" => %{"login" => "sallaumen"}
      }

      assert [%{github_id: temp, author: "you", body: draft}] = Board.comments(task)
      assert temp < 0
      assert draft =~ "hello"
      assert Board.store_comments(task, [remote], "agent")
      refute Board.store_comments(task, [remote], "agent")
      assert Board.store_comments(task, [Map.put(remote, "body", "edit on GitHub")], "agent")
      Req.Test.json(conn, remote)
    end)

    assert {:ok, comment} = Board.ask(task, "hello", client())
    assert [^comment] = Board.comments(task)

    assert {comment.github_id, comment.author, comment.body} ==
             {6_945_214_247, "sallaumen", "edit on GitHub"}
  end

  test "a disconnected send and two identical messages reconcile by receipt, in either order", %{
    task: task
  } do
    parent = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, json, conn} = Plug.Conn.read_body(conn)
      send(parent, {:sent, self(), Jason.decode!(json)["body"]})

      receive do
        {:ack, remote} -> Req.Test.json(conn, remote)
      end
    end)

    {one, ref_one} = spawn_monitor(fn -> Board.ask(task, "same", client()) end)
    assert_receive {:sent, ^one, body_one}
    {two, ref_two} = spawn_monitor(fn -> Board.ask(task, "same", client()) end)
    assert_receive {:sent, ^two, body_two}
    refute body_one == body_two
    assert String.ends_with?(body_one, AgentBoard.Executors.mention_suffix())
    Process.exit(one, :kill)
    assert_receive {:DOWN, ^ref_one, :process, ^one, :killed}
    assert [pending_one, pending_two] = Board.comments(task)
    assert pending_one.github_id < 0 and pending_two.github_id < 0
    assert pending_one.body == pending_two.body
    refute pending_one.body =~ "superboard-delivery"

    remote = fn id, body -> %{"id" => id, "body" => body, "user" => %{"login" => "sallaumen"}} end
    second = remote.(6945, body_two)
    first = remote.(6944, body_one)
    send(two, {:ack, second})
    assert_receive {:DOWN, ^ref_two, :process, ^two, :normal}

    assert Enum.sort(Enum.map(Board.comments(task), & &1.github_id)) == [
             pending_one.github_id,
             6945
           ]

    assert Board.store_comments(task, [second, first], "agent")
    refute Board.store_comments(task, [first, second], "agent")

    assert Enum.sort(Enum.map(Board.comments(task), &{&1.github_id, &1.author, &1.body})) ==
             [{6944, "sallaumen", pending_one.body}, {6945, "sallaumen", pending_two.body}]
  end

  test "stop_task works on a bare task", %{task: task} do
    bare = Repo.get(Task, task.id)

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"number" => 42, "state" => "closed"})
    end)

    assert {:ok, _} = Board.stop_task(bare, client())
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

    assert {:error, %AgentBoard.GitHub.HTTPError{status: 500}} =
             Board.ask(task, "hello", client())

    assert Board.comments(task) == []
  end

  test "a failed request keeps a synced comment stored under a negative id", %{task: task} do
    {:ok, synced} =
      Board.upsert_comment(task, %{"body" => "no id from GitHub"}, "sallaumen-agent")

    assert synced.github_id < 0

    Req.Test.stub(@stub, fn conn ->
      Plug.Conn.send_resp(conn, 500, "boom")
    end)

    assert {:error, %AgentBoard.GitHub.HTTPError{status: 500}} =
             Board.ask(task, "hello", client())

    assert [%{id: id}] = Board.comments(task)
    assert id == synced.id
  end
end
