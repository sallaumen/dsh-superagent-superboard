defmodule AgentBoard.SplitGraphTest do
  @moduledoc "A split's edges are stored here and mirrored on GitHub, without ever undoing an issue."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Actions, Board, Repo, Sync}
  alias AgentBoard.Board.{Objective, SplitGraph, Task, TaskDependency}

  @stub AgentBoard.SplitGraphTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, counter} = Agent.start_link(fn -> 10 end)
    %{repo: repo, counter: counter}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  # Issues are numbered in order and their `id` is 1000 + number. A path
  # matching `refuse` answers 500; every write is sent to the test.
  defp github(counter, refuse \\ fn _path -> false end) do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      path = conn.request_path

      cond do
        refuse.(path) ->
          Plug.Conn.send_resp(conn, 500, "boom")

        conn.method == "GET" ->
          number = path |> Path.basename() |> String.to_integer()
          Req.Test.json(conn, %{"id" => 1000 + number, "number" => number})

        String.ends_with?(path, "/issues") ->
          number = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
          send(test_pid, {:issue, number, Jason.decode!(raw)})
          Req.Test.json(conn, %{"number" => number, "html_url" => "https://x/#{number}"})

        true ->
          send(test_pid, {:link, path, Jason.decode!(raw)})
          Req.Test.json(conn, %{})
      end
    end)
  end

  defp request(repo, title, depends_on) do
    %{
      title: title,
      body: "Corpo de #{title}",
      key: key(repo, title),
      language: "pt",
      depends_on: Enum.map(depends_on, &key(repo, &1))
    }
  end

  defp key(repo, title), do: Board.request_key(repo, "split", [title])

  defp params(repo, requests) do
    %{
      repository: repo,
      requests: requests,
      client: client(),
      objective: %{
        title: "Jogo",
        done_criterion: "Tudo mesclado.",
        request_key: Board.request_key(repo, "objective", ["jogo"]),
        request_text: "Melhorar o jogo, @sallaumen-agent",
        spec: %{"goal" => "Melhorar", "language" => "pt"}
      }
    }
  end

  defp create(repo, requests) do
    params = params(repo, requests)

    Actions.run(:create_tasks, params, Actions.owner(:ui),
      confirm: Actions.phrase(:create_tasks, params)
    )
  end

  test "the edges are stored and the group is mirrored on GitHub", %{repo: repo, counter: counter} do
    github(counter)

    assert {:ok, _results} =
             create(repo, [request(repo, "Dados", []), request(repo, "Tela", ["Dados"])])

    dados = Repo.get_by!(Task, title: "Dados")
    tela = Repo.get_by!(Task, title: "Tela")

    assert [%TaskDependency{task_id: task, blocked_by_task_id: blocker}] =
             Repo.all(TaskDependency)

    assert {task, blocker} == {tela.id, dados.id}

    assert_received {:issue, 13, parent}
    assert parent["labels"] == ["board:objective"]
    assert parent["body"] =~ "## Pedido original\nMelhorar o jogo"
    assert parent["body"] =~ "- #11 Dados"
    assert parent["body"] =~ "- #12 Tela"
    # A group of tasks is nobody's work: it must not wake the agent.
    refute parent["body"] =~ "@sallaumen-agent"

    assert %Objective{issue_number: 13} = Repo.one(Objective)

    assert_received {:link, "/repos/sallaumen/arena-rogue/issues/13/sub_issues",
                     %{"sub_issue_id" => 1011}}

    assert_received {:link, "/repos/sallaumen/arena-rogue/issues/13/sub_issues",
                     %{"sub_issue_id" => 1012}}

    assert_received {:link, "/repos/sallaumen/arena-rogue/issues/12/dependencies/blocked_by",
                     %{"issue_id" => 1011}}
  end

  test "a link GitHub refuses is an event and the tasks stay", %{repo: repo, counter: counter} do
    github(counter, &String.ends_with?(&1, "/blocked_by"))

    assert {:ok, [{_, {:ok, %Task{}, :created}}, {_, {:ok, %Task{}, :created}}]} =
             create(repo, [request(repo, "Dados", []), request(repo, "Tela", ["Dados"])])

    assert Repo.aggregate(Task, :count) == 2
    assert Repo.aggregate(TaskDependency, :count) == 1
    assert_received {:link, _sub_issues, %{"sub_issue_id" => _}}
    assert [_one] = Board.events(repo, 20) |> Enum.filter(&(&1.kind == "link_error"))
  end

  test "a split that failed publishes only when the retry completes it, once", %{
    repo: repo,
    counter: counter
  } do
    {:ok, down} = Agent.start_link(fn -> true end)

    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    requests = [request(repo, "Dados", []), request(repo, "Tela", [])]

    first = fn ->
      github(counter, fn path ->
        Agent.get(down, & &1) and String.ends_with?(path, "/issues") and
          Agent.get(counter, & &1) >= 11
      end)

      create(repo, requests)
    end

    assert {:ok, [{_, {:ok, %Task{}, :created}}, {_, {:error, _}}]} = first.()
    refute_received {:issue, 12, _}

    Agent.update(down, fn _ -> false end)

    assert {:ok, [{_, {:ok, %Task{}, :existing}}, {_, {:ok, %Task{}, :created}}]} =
             create(repo, requests)

    assert_received {:issue, 13, %{"labels" => ["board:objective"]}}
    assert Repo.aggregate(Objective, :count) == 1

    assert {:ok, _again} = create(repo, requests)
    refute_received {:issue, 14, _}
  end

  test "the sync leaves a group's issue out of the queue", %{repo: repo} do
    issue = fn number, labels ->
      %{
        "number" => number,
        "title" => "Issue #{number}",
        "state" => "open",
        "html_url" => "https://x/#{number}",
        "user" => %{"login" => "sallaumen"},
        "labels" => labels
      }
    end

    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [
            issue.(7, []),
            issue.(8, [%{"name" => SplitGraph.objective_label()}])
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert [%Task{number: 7}] = Repo.all(Task)
  end
end
