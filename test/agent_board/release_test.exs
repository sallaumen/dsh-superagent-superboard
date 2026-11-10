defmodule AgentBoard.ReleaseTest do
  @moduledoc "A task waits for what it depends on, and the agent is called once."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Actions, Board, Release, Repo}
  alias AgentBoard.Board.{Task, TaskDependency}

  @stub AgentBoard.ReleaseTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  defp github(status \\ 201) do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:comment, conn.request_path, Jason.decode!(raw)})
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
    end)
  end

  defp task(repo, number, state, attrs \\ %{}) do
    %Task{}
    |> Task.changeset(
      Map.merge(
        %{
          repository_id: repo.id,
          kind: "issue",
          number: number,
          title: "T#{number}",
          state: state
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp waits(task, blocker) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(TaskDependency, [
      %{task_id: task.id, blocked_by_task_id: blocker.id, inserted_at: now, updated_at: now}
    ])
  end

  test "a held task is called once its dependencies finished, and only once", %{repo: repo} do
    github()
    blocker = task(repo, 1, "done")
    held = task(repo, 2, "queued", %{held: true})
    waits(held, blocker)

    assert [{2, :ok}] = Release.tick(client())

    assert_received {:comment, "/repos/sallaumen/arena-rogue/issues/2/comments",
                     %{"body" => body}}

    assert body =~ "@sallaumen-agent"
    assert %Task{held: false, released_at: %DateTime{}} = Repo.get!(Task, held.id)

    assert [] = Release.tick(client())
    refute_received {:comment, _, _}
  end

  test "an open dependency holds the task", %{repo: repo} do
    github()
    held = task(repo, 2, "queued", %{held: true})
    waits(held, task(repo, 1, "running"))

    assert [] = Release.tick(client())
    refute_received {:comment, _, _}
  end

  test "every dependency must finish", %{repo: repo} do
    github()
    held = task(repo, 3, "queued", %{held: true})
    waits(held, task(repo, 1, "done"))
    waits(held, task(repo, 2, "blocked"))

    assert [] = Release.tick(client())
  end

  test "a task whose edges were not written yet is not released", %{repo: repo} do
    github()
    task(repo, 2, "queued", %{held: true})

    assert [] = Release.tick(client())
  end

  test "a stopped task stays where the owner left it", %{repo: repo} do
    github()
    held = task(repo, 2, "queued", %{held: true, stopped: true})
    waits(held, task(repo, 1, "done"))

    assert [] = Release.tick(client())
  end

  test "a comment that failed is not repeated by itself", %{repo: repo} do
    github(500)
    held = task(repo, 2, "queued", %{held: true})
    waits(held, task(repo, 1, "done"))

    assert [{2, {:error, _}}] = Release.tick(client())
    assert_received {:comment, _, _}
    assert %Task{held: true, released_at: %DateTime{}} = Repo.get!(Task, held.id)
    assert [] = Release.tick(client())
    refute_received {:comment, _, _}
    assert Enum.any?(Board.events(repo, 5), &(&1.kind == "release_error"))
  end

  test "only the release may act without the owner, and the owner confirms", %{repo: repo} do
    github()
    held = task(repo, 2, "queued", %{held: true})
    params = %{task: held, repository: repo, client: client()}

    assert {:error, {:unconfirmed, _}} =
             Actions.run(:release_task, params, Actions.system("sync"))

    refute_received {:comment, _, _}

    phrase = Actions.phrase(:release_task, params)
    assert phrase =~ "#2"
    assert :ok = Actions.run(:release_task, params, Actions.owner(:ui), confirm: phrase)
    assert_received {:comment, _, _}
  end

  test "the comment names its task, so calls made together stay apart", %{repo: repo} do
    github()
    held = task(repo, 2, "queued", %{held: true})
    waits(held, task(repo, 1, "done"))

    assert [{2, :ok}] = Release.tick(client())
    assert_received {:comment, _path, %{"body" => body}}
    assert body =~ "#2 T2"
    assert String.ends_with?(body, "@sallaumen-agent")
  end

  test "the owner can call again a task the agent never took", %{repo: repo} do
    github()
    called = ~U[2026-11-09 20:47:31Z]
    stuck = task(repo, 2, "queued", %{released_at: called, executor: "dsh"})
    params = %{task: stuck, repository: repo, client: client()}
    phrase = Actions.phrase(:release_task, params)

    assert :ok = Actions.run(:release_task, params, Actions.owner(:ui), confirm: phrase)
    assert_received {:comment, "/repos/sallaumen/arena-rogue/issues/2/comments", _body}
    assert %Task{released_at: again} = Repo.get!(Task, stuck.id)
    assert DateTime.compare(again, called) == :gt
  end

  test "a task that is running, or that the runner was never called on, is not called", %{
    repo: repo
  } do
    github()

    for {number, state, attrs} <- [
          {2, "running", %{released_at: ~U[2026-11-09 20:47:31Z], executor: "dsh"}},
          {3, "queued", %{executor: "claude"}}
        ] do
      params = %{task: task(repo, number, state, attrs), repository: repo, client: client()}
      phrase = Actions.phrase(:release_task, params)

      assert {:error, :not_waiting} =
               Actions.run(:release_task, params, Actions.owner(:ui), confirm: phrase)
    end

    refute_received {:comment, _, _}
  end

  describe "creating a split" do
    defp stub_creation do
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      test_pid = self()

      Req.Test.stub(@stub, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        number = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
        send(test_pid, {:issue, number, Jason.decode!(raw)})
        Req.Test.json(conn, %{"number" => number, "html_url" => "https://x/#{number}"})
      end)
    end

    defp request(repo, title, depends_on, attrs \\ %{}) do
      Map.merge(
        %{
          title: title,
          body: "Corpo de #{title}\n\n@sallaumen-agent",
          key: Board.request_key(repo, "split", [title]),
          language: "pt",
          depends_on: Enum.map(depends_on, &Board.request_key(repo, "split", [&1]))
        },
        attrs
      )
    end

    test "what depends on another opens without calling the agent", %{repo: repo} do
      stub_creation()
      requests = [request(repo, "Dados", []), request(repo, "Tela", ["Dados"])]

      Board.Requests.create_requests(repo, requests, client())

      assert_received {:issue, 1, %{"body" => free}}
      assert free =~ "@sallaumen-agent"
      assert_received {:issue, 2, %{"body" => waiting}}
      refute waiting =~ "@"
      assert waiting =~ "**Depende de:** #1"
      assert %Task{held: true} = Repo.get_by!(Task, title: "Tela")
      assert %Task{held: false} = Repo.get_by!(Task, title: "Dados")
    end

    test "the sentence the owner confirms says the tree is released in order", %{repo: repo} do
      requests = [request(repo, "Dados", []), request(repo, "Tela", ["Dados"])]

      assert Actions.phrase(:create_tasks, %{repository: repo, requests: requests}) =~
               "o board chama o agente"

      refute Actions.phrase(:create_tasks, %{repository: repo, requests: Enum.take(requests, 1)}) =~
               "o board chama o agente"
    end
  end
end
