defmodule AgentBoard.CreateRequestTest do
  @moduledoc "A board request is created once: the key is the receipt."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Actions, Board, Repo, Routing}
  alias AgentBoard.Board.Task
  alias AgentBoard.Routing.Decision

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

  test "a split with more than one task creates one objective", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    requests = [
      %{
        title: "Placar",
        body: "Placar\n\n@sallaumen-agent",
        key: Board.request_key(repo, "split", ["Placar"])
      },
      %{
        title: "Mapa",
        body: "Mapa\n\n@sallaumen-agent",
        key: Board.request_key(repo, "split", ["Mapa"])
      }
    ]

    params = %{
      repository: repo,
      requests: requests,
      client: client(),
      objective: %{title: "Jogo", done_criterion: "As duas telas mescladas."}
    }

    phrase = Actions.phrase(:create_tasks, params)

    assert {:ok, results} =
             Actions.run(:create_tasks, params, Actions.owner(:ui), confirm: phrase)

    assert length(results) == 2
    assert [objective] = Board.objectives(repo)
    assert objective.title == "Jogo"
    assert objective.total == 2
    assert objective.merged == 0
  end

  # Answers every issue creation and sends the test the JSON GitHub received.
  defp capture_issues do
    test = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:issue, Jason.decode!(body)})
      Req.Test.json(conn, %{"number" => 7, "html_url" => "https://github.com/x/y/issues/7"})
    end)
  end

  test "a task for Claude Code opens an issue without the mention, labelled for it",
       %{repo: repo} do
    capture_issues()
    body = "Refazer a tela\n\n@sallaumen-agent"
    key = Board.request_key(repo, "single", ["Refazer a tela", body])

    assert {:ok, task, :created} =
             Board.create_request(
               repo,
               %{title: "Refazer a tela", body: body, key: key, executor: "claude"},
               client()
             )

    assert_received {:issue, sent}
    refute sent["body"] =~ "@sallaumen-agent"
    assert sent["labels"] == ["executor:claude"]
    assert %Task{executor: "claude", body: "Refazer a tela"} = Repo.get(Task, task.id)

    # The same words again are the same task, not a second issue.
    assert {:ok, %Task{id: id}, :existing} =
             Board.create_request(
               repo,
               %{title: "Refazer a tela", body: body, key: key, executor: "claude"},
               client()
             )

    assert id == task.id
    refute_received {:issue, _}
  end

  test "a task for the DeepSeek runner keeps the mention and is labelled for it", %{repo: repo} do
    capture_issues()
    key = Board.request_key(repo, "single", ["Add a boss", "Add a boss"])

    assert {:ok, task, :created} =
             Board.create_request(
               repo,
               %{title: "Add a boss", body: "Add a boss", key: key, executor: "dsh"},
               client()
             )

    assert_received {:issue, %{"body" => "Add a boss\n\n@sallaumen-agent", "labels" => labels}}
    assert labels == ["executor:dsh"]
    assert Repo.get(Task, task.id).executor == "dsh"
  end

  test "the router's suggestion and the owner's choice are one row per created task",
       %{repo: repo} do
    capture_issues()
    signals = Routing.Signals.read(fn -> {:error, :unreachable} end, fn -> %{} end)

    suggestion =
      Routing.suggest(%{repository: "sallaumen/arena-rogue", work_type: "ui"}, signals)

    request = %{
      title: "Refazer a tela",
      body: "Refazer a tela",
      key: Board.request_key(repo, "single", ["Refazer a tela"]),
      executor: "codex",
      routing: %{
        suggestion: suggestion,
        signals: Routing.Signals.snapshot(signals),
        decided_by: "composer"
      }
    }

    assert {:ok, task, :created} = Board.create_request(repo, request, client())
    assert {:ok, _task, :existing} = Board.create_request(repo, request, client())

    assert [decision] = Repo.all(Decision)
    assert decision.task_id == task.id
    assert {decision.suggested, decision.chosen} == {"dsh", "codex"}
    assert decision.mode == "suggest"
    assert decision.decided_by == "composer"
    assert decision.alternatives == ["claude", "codex"]
    assert Enum.any?(decision.reasons, &(&1 =~ "Não deu para ler qual repositório"))
    assert decision.signals["dsh"]["state"] == "unavailable: o orquestrador não respondeu"
    assert decision.signals["claude"]["state"] == "unknown"
  end

  test "a request for an executor without a suggestion gets the router's line anyway",
       %{repo: repo} do
    capture_issues()

    request = %{
      title: "Add a boss",
      body: "Add a boss",
      key: Board.request_key(repo, "single", ["Add a boss"]),
      executor: "claude"
    }

    assert {:ok, task, :created} = Board.create_request(repo, request, client())

    # The owner's explicit choice decides, whatever the router reads.
    assert %Decision{suggested: "claude", chosen: "claude", decided_by: "api"} =
             Repo.get_by(Decision, task_id: task.id)
  end

  test "a request without an executor is opened as given, with no label", %{repo: repo} do
    capture_issues()
    body = "Add a boss\n\n@sallaumen-agent"
    key = Board.request_key(repo, "single", ["Add a boss", body])

    assert {:ok, task, :created} =
             Board.create_request(repo, %{title: "Add a boss", body: body, key: key}, client())

    assert_received {:issue, sent}
    assert sent["body"] == body
    refute Map.has_key?(sent, "labels")
    assert Repo.get(Task, task.id).executor == nil
    assert Repo.all(Decision) == []
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
