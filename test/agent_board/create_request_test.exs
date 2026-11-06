defmodule AgentBoard.CreateRequestTest do
  @moduledoc "A board request is created once: the key is the receipt."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @stub AgentBoard.CreateRequestTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  defp count_issues(counter) do
    Req.Test.stub(@stub, fn conn ->
      number = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

      Req.Test.json(conn, %{
        "number" => number,
        "html_url" => "https://github.com/x/y/issues/#{number}"
      })
    end)
  end

  test "the same request submitted twice opens one issue", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    key = Board.request_key(repo, "single", ["Add a boss", "Add a boss\n\n@sallaumen-agent"])
    request = %{title: "Add a boss", body: "Add a boss\n\n@sallaumen-agent", key: key}

    assert {:ok, first, :created} = Board.create_request(repo, request, client())
    assert {:ok, again, :existing} = Board.create_request(repo, request, client())

    assert again.id == first.id
    assert Agent.get(counter, & &1) == 1
    assert Repo.aggregate(Task, :count) == 1
    assert Repo.get(Task, first.id).request_key == key
  end

  test "the key ignores spacing differences and keeps distinct requests apart", %{repo: repo} do
    assert Board.request_key(repo, "single", ["a  b", "x"]) ==
             Board.request_key(repo, "single", [" a b ", "x"])

    refute Board.request_key(repo, "single", ["a", "x"]) ==
             Board.request_key(repo, "single", ["b", "x"])

    refute Board.request_key(repo, "single", ["a", "x"]) ==
             Board.request_key(repo, "split", ["a", "x"])
  end

  test "a queued task the sync stored with the same words is the receipt", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    # The sync saw the issue before the board recorded a key (no key column).
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 50,
      title: "Add a boss",
      body: "Add a boss\n\n@sallaumen-agent",
      state: "queued"
    })
    |> Repo.insert!()

    key = Board.request_key(repo, "single", ["Add a boss", "Add a boss\n\n@sallaumen-agent"])
    request = %{title: "Add a boss", body: "Add a boss\n\n@sallaumen-agent", key: key}

    assert {:ok, task, :existing} = Board.create_request(repo, request, client())
    assert task.number == 50
    assert Agent.get(counter, & &1) == 0
  end

  test "a done task with the same words is not a receipt: the request is new", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 50,
      title: "Add a boss",
      body: "Add a boss\n\n@sallaumen-agent",
      state: "done"
    })
    |> Repo.insert!()

    key = Board.request_key(repo, "single", ["Add a boss", "Add a boss\n\n@sallaumen-agent"])
    request = %{title: "Add a boss", body: "Add a boss\n\n@sallaumen-agent", key: key}

    assert {:ok, _task, :created} = Board.create_request(repo, request, client())
    assert Agent.get(counter, & &1) == 1
  end

  test "a GitHub failure is an error and leaves no task", %{repo: repo} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    key = Board.request_key(repo, "single", ["T", "body"])

    assert {:error, _} =
             Board.create_request(repo, %{title: "T", body: "body", key: key}, client())

    assert Repo.aggregate(Task, :count) == 0
  end

  test "a split task records its origin", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    origin =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, kind: "issue", number: 999, title: "Origin"})
      |> Repo.insert!()

    key = Board.request_key(repo, "split", ["Origin text", "Part 1"])

    assert {:ok, task, :created} =
             Board.create_request(
               repo,
               %{title: "Part 1", body: "b", key: key, origin_task_id: origin.id},
               client()
             )

    assert Repo.get(Task, task.id).origin_task_id == origin.id
  end
end
