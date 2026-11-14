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

  @signals %{
    "dsh" => %{
      repository: "sallaumen/arena-rogue",
      state: :ready,
      load: %{running: 0, max_workers: 3}
    },
    "claude" => %{state: :unknown},
    "codex" => %{state: :unknown}
  }

  # A request for a named executor carries the line its door built. The
  # decision itself is pure; this fixture keeps the context test focused on
  # "create once", not on reading the runner.
  defp routed(repo, request, requested \\ nil, decided_by \\ "api") do
    requested = requested || Map.get(request, :executor)
    Routing.plan(repo, request, requested, decided_by, @signals)
  end

  defp count_issues(counter) do
    Req.Test.stub(@stub, fn conn ->
      number = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

      Req.Test.json(conn, %{
        "number" => number,
        "html_url" => "https://github.com/x/y/issues/#{number}"
      })
    end)
  end

  test "a blocker request keeps the link to the blocked task", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    blocked =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 1417,
        title: "Menu central",
        state: "blocked"
      })
      |> Repo.insert!()

    request =
      routed(repo, %{
        title: "Desbloquear #1417",
        body: "Corpo\n\n@sallaumen-agent",
        key: Board.request_key(repo, "unblock", ["Desbloquear #1417", "Corpo"]),
        executor: "dsh",
        origin_task_id: blocked.id,
        blocker_for_task_id: blocked.id
      })

    assert {:ok, blocker, :created} = Board.Requests.create_request(repo, request, client())
    assert blocker.blocker_for_task_id == blocked.id
    assert blocker.origin_task_id == blocked.id
    assert [^blocker] = Board.blockers_for(blocked)
  end

  test "the same request submitted twice opens one issue", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    key = Board.request_key(repo, "single", ["Add a boss", "Add a boss\n\n@sallaumen-agent"])
    request = %{title: "Add a boss", body: "Add a boss\n\n@sallaumen-agent", key: key}

    assert {:ok, first, :created} = Board.Requests.create_request(repo, request, client())
    assert {:ok, again, :existing} = Board.Requests.create_request(repo, request, client())

    assert again.id == first.id
    assert Agent.get(counter, & &1) == 1
    assert Repo.aggregate(Task, :count) == 1
    assert Repo.get(Task, first.id).request_key == key
  end

  for {state, flags} <- [
        {"done", []},
        {"closed", []},
        {"stopped", [stopped: true]},
        {"archived", [archived: true]}
      ] do
    test "the same words after a #{state} task open a new issue", %{repo: repo} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      count_issues(counter)

      key = Board.request_key(repo, "single", ["Add a boss", "Corpo"])
      request = %{title: "Add a boss", body: "Corpo", key: key}

      assert {:ok, first, :created} = Board.Requests.create_request(repo, request, client())

      first
      |> Ecto.Changeset.change([state: unquote(state)] ++ unquote(flags))
      |> Repo.update!()

      assert {:ok, second, :created} = Board.Requests.create_request(repo, request, client())

      assert second.id != first.id
      assert Agent.get(counter, & &1) == 2
      assert Repo.get(Task, first.id).request_key == nil
      assert Repo.get(Task, second.id).request_key == key
    end
  end

  test "the same words while the task is still open answer the receipt", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    key = Board.request_key(repo, "single", ["Add a boss", "Corpo"])
    request = %{title: "Add a boss", body: "Corpo", key: key}

    assert {:ok, first, :created} = Board.Requests.create_request(repo, request, client())
    first |> Ecto.Changeset.change(state: "running") |> Repo.update!()

    assert {:ok, again, :existing} = Board.Requests.create_request(repo, request, client())
    assert again.id == first.id
    assert Agent.get(counter, & &1) == 1
    assert Repo.get(Task, first.id).request_key == key
  end

  test "the same words while the first is being created wait for it", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    count_issues(counter)

    key = Board.request_key(repo, "single", ["Add a boss", "Corpo"])

    claim =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        title: "Add a boss",
        body: "Corpo",
        state: "draft",
        request_key: key
      })
      |> Repo.insert!()

    request = %{title: "Add a boss", body: "Corpo", key: key}

    assert {:error, :in_progress} = Board.Requests.create_request(repo, request, client())
    assert Agent.get(counter, & &1) == 0
    assert Repo.get(Task, claim.id).request_key == key
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

  # Issues are numbered in the order they reach GitHub. Every title and body
  # is sent to the test; a title in `refuse` answers 500.
  defp record_issues(counter, refuse \\ fn _title -> false end) do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      %{"title" => title, "body" => body} = Jason.decode!(raw)

      if refuse.(title) do
        Plug.Conn.send_resp(conn, 500, "boom")
      else
        number = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
        send(test_pid, {:issue, number, title, body})
        Req.Test.json(conn, %{"number" => number, "html_url" => "https://x/#{number}"})
      end
    end)
  end

  defp linked(repo, title, depends_on \\ []) do
    %{
      title: title,
      body: "Corpo de #{title}",
      key: key(repo, title),
      language: "pt",
      depends_on: Enum.map(depends_on, &key(repo, &1))
    }
  end

  defp key(repo, title), do: Board.request_key(repo, "split", [title])

  test "a task is opened after what it depends on and names its number", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 40 end)
    record_issues(counter)

    requests = [linked(repo, "Tela", ["Dados"]), linked(repo, "Dados")]

    results = Board.Requests.create_requests(repo, requests, client())

    assert_received {:issue, 41, "Dados", dados}
    refute dados =~ "Depende de"
    assert_received {:issue, 42, "Tela", tela}
    assert String.starts_with?(tela, "**Depende de:** #41")

    # The receipt keeps the order the owner reviewed.
    assert [{%{title: "Tela"}, {:ok, %Task{number: 42}, :created}}, {%{title: "Dados"}, _}] =
             results
  end

  test "a blocker that failed holds its dependent back, and the retry opens it", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    {:ok, down} = Agent.start_link(fn -> true end)
    record_issues(counter, fn title -> title == "Dados" and Agent.get(down, & &1) end)

    requests = [linked(repo, "Dados"), linked(repo, "Tela", ["Dados"])]

    assert [{_, {:error, _reason}}, {_, {:error, :dependency_failed}}] =
             Board.Requests.create_requests(repo, requests, client())

    refute_received {:issue, _, _, _}
    assert Repo.aggregate(Task, :count) == 0

    Agent.update(down, fn _ -> false end)

    assert [{_, {:ok, %Task{number: 1}, :created}}, {_, {:ok, %Task{number: 2}, :created}}] =
             Board.Requests.create_requests(repo, requests, client())

    assert_received {:issue, 2, "Tela", tela}
    assert tela =~ "#1"
  end

  test "a cycle from the model still opens every task", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    record_issues(counter)

    requests = [linked(repo, "A", ["B"]), linked(repo, "B", ["A"])]

    assert [{_, {:ok, %Task{}, :created}}, {_, {:ok, %Task{}, :created}}] =
             Board.Requests.create_requests(repo, requests, client())

    # A was opened first, when B had no number to name.
    assert_received {:issue, 1, "A", first}
    refute first =~ "Depende de"
    assert_received {:issue, 2, "B", second}
    assert second =~ "**Depende de:** #1"
  end

  test "two tasks with the same title each get their own receipt", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    record_issues(counter)

    requests = [linked(repo, "Igual"), linked(repo, "Igual")]

    assert [{_, {:ok, %Task{number: 1}, :created}}, {_, {:ok, %Task{number: 1}, :existing}}] =
             Board.Requests.create_requests(repo, requests, client())
  end

  test "a claim left by a process that died does not hold the request forever", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    record_issues(counter)
    long_ago = DateTime.utc_now() |> DateTime.add(-600, :second) |> DateTime.truncate(:second)

    Repo.insert!(%Task{
      repository_id: repo.id,
      kind: "issue",
      title: "Dados",
      body: "Corpo de Dados",
      state: "draft",
      request_key: key(repo, "Dados"),
      inserted_at: long_ago,
      updated_at: long_ago
    })

    requests = [linked(repo, "Dados"), linked(repo, "Tela", ["Dados"])]

    assert [{_, {:ok, %Task{number: 1}, :created}}, {_, {:ok, %Task{number: 2}, :created}}] =
             Board.Requests.create_requests(repo, requests, client())
  end

  test "a task outside a cycle still names the task of the cycle it waits for", %{repo: repo} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    record_issues(counter)

    requests = [linked(repo, "C", ["A"]), linked(repo, "A", ["B"]), linked(repo, "B", ["A"])]

    assert [{_, {:ok, %Task{}, :created}} | _] =
             Board.Requests.create_requests(repo, requests, client())

    assert_received {:issue, 1, "A", _first}
    assert_received {:issue, _number, "C", waiting}
    assert waiting =~ "**Depende de:** #1"
  end

  test "a claim already in progress is not a second issue", %{repo: repo} do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called") end)

    key = Board.request_key(repo, "single", ["Em andamento"])
    body = "Em andamento\n\n@sallaumen-agent"

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      title: "Em andamento",
      body: body,
      state: "draft",
      request_key: key
    })
    |> Repo.insert!()

    assert {:error, :in_progress} =
             Board.Requests.create_request(
               repo,
               %{title: "Em andamento", body: body, key: key},
               client()
             )

    assert Repo.aggregate(Task, :count) == 1
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

    request = routed(repo, %{title: "Refazer a tela", body: body, key: key, executor: "claude"})

    assert {:ok, task, :created} = Board.Requests.create_request(repo, request, client())

    assert_received {:issue, sent}
    refute sent["body"] =~ "@sallaumen-agent"
    assert sent["labels"] == ["executor:claude"]
    assert %Task{executor: "claude", body: "Refazer a tela"} = Repo.get(Task, task.id)

    # The same words again are the same task, not a second issue.
    assert {:ok, %Task{id: id}, :existing} =
             Board.Requests.create_request(repo, request, client())

    assert id == task.id
    refute_received {:issue, _}
  end

  test "a task for the DeepSeek runner keeps the mention and is labelled for it", %{repo: repo} do
    capture_issues()
    key = Board.request_key(repo, "single", ["Add a boss", "Add a boss"])

    request = routed(repo, %{title: "Add a boss", body: "Add a boss", key: key, executor: "dsh"})

    assert {:ok, task, :created} = Board.Requests.create_request(repo, request, client())

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
        signals: Routing.snapshot(signals),
        decided_by: "composer"
      }
    }

    assert {:ok, task, :created} = Board.Requests.create_request(repo, request, client())
    assert {:ok, _task, :existing} = Board.Requests.create_request(repo, request, client())

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

  test "the write door builds the router line for an executor-only request",
       %{repo: repo} do
    capture_issues()

    request = %{
      title: "Add a boss",
      body: "Add a boss",
      key: Board.request_key(repo, "single", ["Add a boss"]),
      executor: "claude"
    }

    params = %{repository: repo, requests: [request], client: client()}
    phrase = Actions.phrase(:create_tasks, params)

    assert {:ok, [{_request, {:ok, task, :created}}]} =
             Actions.run(:create_tasks, params, Actions.owner(:ui), confirm: phrase)

    # The owner's explicit choice decides, whatever the router reads; the
    # line is still recorded by the door, not silently by the Board.
    assert %Decision{suggested: "claude", chosen: "claude", decided_by: "api"} =
             Repo.get_by(Decision, task_id: task.id)
  end

  test "the write door refuses a runner request for a repository the runner does not watch",
       %{repo: repo} do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called") end)
    {:ok, watched} = Board.add_repository("sallaumen", "o_colmex")

    {:ok, _superagent} =
      AgentBoard.Superagents.create(%{
        repository_id: watched.id,
        profile: "superagent-o-colmex",
        port: 3411,
        state_dir: "/tmp/superagent-o-colmex"
      })

    # The blocker task (`Unblock.request/4`) and a confirmed voice proposal
    # reach the door like this: an executor already named, no router line.
    request = %{
      title: "Add a boss",
      body: "Add a boss",
      key: Board.request_key(repo, "unblock", ["Add a boss"]),
      executor: "dsh"
    }

    params = %{repository: repo, requests: [request], client: client()}
    phrase = Actions.phrase(:create_tasks, params)

    assert {:ok, [{_request, {:error, "o DeepSeek só atende o sallaumen/o_colmex."}}]} =
             Actions.run(:create_tasks, params, Actions.owner(:ui), confirm: phrase)

    assert Repo.aggregate(Task, :count) == 0
  end

  test "the board refuses an executor request without a router line", %{repo: repo} do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called") end)

    request = %{
      title: "Add a boss",
      body: "Add a boss",
      key: Board.request_key(repo, "single", ["Add a boss"]),
      executor: "claude"
    }

    assert {:error, :not_routed} = Board.Requests.create_request(repo, request, client())
    assert Repo.aggregate(Task, :count) == 0
  end

  test "a request without an executor is opened as given, with no label", %{repo: repo} do
    capture_issues()
    body = "Add a boss\n\n@sallaumen-agent"
    key = Board.request_key(repo, "single", ["Add a boss", body])

    assert {:ok, task, :created} =
             Board.Requests.create_request(
               repo,
               %{title: "Add a boss", body: body, key: key},
               client()
             )

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

    assert {:ok, task, :existing} = Board.Requests.create_request(repo, request, client())
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

    assert {:ok, _task, :created} = Board.Requests.create_request(repo, request, client())
    assert Agent.get(counter, & &1) == 1
  end

  test "a synced issue wins the row while the board keeps its request metadata", %{repo: repo} do
    origin =
      Repo.insert!(%Task{repository_id: repo.id, kind: "issue", number: 18, title: "Origin"})

    caller = self()

    Req.Test.stub(@stub, fn conn ->
      mirrored =
        Repo.insert!(%Task{
          repository_id: repo.id,
          kind: "issue",
          number: 71,
          title: "Updated upstream",
          body: "Edited upstream",
          state: "running"
        })

      Repo.insert!(%AgentBoard.Board.Comment{task_id: mirrored.id, body: "Already working on it"})
      send(caller, {:mirrored, mirrored.id})
      Req.Test.json(conn, %{"number" => 71, "html_url" => "https://example.org/issues/71"})
    end)

    request =
      routed(repo, %{
        title: "Split task",
        body: "Original",
        key: "split-71",
        executor: "dsh",
        held: true,
        origin_task_id: origin.id,
        blocker_for_task_id: origin.id,
        work_type: "ui",
        size: "S"
      })

    assert {:ok, task, :created} = Board.Requests.create_request(repo, request, client())
    assert_receive {:mirrored, id}
    assert task.id == id
    task = Repo.get!(Task, id)

    assert {task.number, task.state, task.title, task.body} ==
             {71, "running", "Updated upstream", "Edited upstream"}

    assert {task.request_key, task.executor, task.held, task.work_type, task.size} ==
             {"split-71", "dsh", true, "ui", "S"}

    assert task.origin_task_id == origin.id and task.blocker_for_task_id == origin.id
    assert [%{body: "Already working on it"}] = Board.comments(task)
    assert [%{task_id: ^id}] = Repo.all(Decision)
    assert Repo.aggregate(Task, :count) == 2

    assert {:ok, %Task{id: ^id}, :existing} =
             Board.Requests.create_request(repo, request, client())

    refute_received {:mirrored, _}
  end

  test "a GitHub failure is an error and leaves no task", %{repo: repo} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    key = Board.request_key(repo, "single", ["T", "body"])

    assert {:error, _} =
             Board.Requests.create_request(repo, %{title: "T", body: "body", key: key}, client())

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
             Board.Requests.create_request(
               repo,
               %{title: "Part 1", body: "b", key: key, origin_task_id: origin.id},
               client()
             )

    assert Repo.get(Task, task.id).origin_task_id == origin.id
  end

  test "a title past what the column holds opens the issue with it clipped", %{repo: repo} do
    title = String.duplicate("t", 300)
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:issue_title, Jason.decode!(raw)["title"]})

      Req.Test.json(conn, %{"number" => 77, "html_url" => "https://github.com/x/y/issues/77"})
    end)

    request = %{title: title, body: "corpo", key: "long-title"}

    assert {:ok, %Task{} = task, :created} =
             Board.Requests.create_request(repo, request, client())

    assert String.length(task.title) == 255
    assert_receive {:issue_title, sent}
    assert String.length(sent) == 255

    assert {:ok, %Task{id: same}, _repeat} =
             Board.Requests.create_request(repo, request, client())

    assert same == task.id
  end

  test "an event subject past the column is clipped, not an error", %{repo: repo} do
    assert {:ok, event} = Board.log_event(repo.id, "create_error", String.duplicate("s", 300))
    assert String.length(event.subject) == 255
  end
end
