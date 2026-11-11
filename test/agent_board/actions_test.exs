defmodule AgentBoard.ActionsTest do
  @moduledoc """
  The registry of the board's writes: one test per action, the gate that
  refuses a red action without a confirmation, the record of every
  decision, and a read of `lib/` that fails on a write outside the registry.
  """
  use AgentBoard.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  # Refusals and failed effects are exercised on purpose.
  @moduletag capture_log: true

  alias AgentBoard.{Actions, Board, Conversation, Orchestrator, Repo, Settings, Voice}
  alias AgentBoard.Actions.Decision
  alias AgentBoard.Board.{Comment, PrivateContext, Task}
  alias AgentBoard.Runners.Execution
  alias AgentBoard.Superagents
  alias AgentBoard.Superagents.{FakeManager, FakeProvisioner}

  @github AgentBoard.ActionsTest.GitHub
  @orchestrator AgentBoard.ActionsTest.Orchestrator

  # Every action has its own test below; a new action fails this list first.
  @tested [
    :create_tasks,
    :ask_task,
    :share_private_context,
    :stop_task,
    :undo_created_task,
    :archive_task,
    :resume_task,
    :retry_ticket,
    :auto_retry_ticket,
    :release_task,
    :dispatch_task,
    :stop_execution,
    :provision_superagent,
    :retry_provision_superagent,
    :remove_superagent,
    :start_superagent,
    :stop_superagent,
    :pause_superagent,
    :resume_superagent,
    :scale_superagent,
    :grant_agent_access,
    :revoke_agent_access,
    :dismiss_access_request,
    :start_agent,
    :set_max_workers,
    :add_repository,
    :change_setting,
    :dismiss_summary,
    :forget_conversation,
    :sync_now,
    :update_board,
    :restart_board
  ]

  defmodule UpdaterStub do
    def pull, do: {:ok, "abc1234"}

    def restart,
      do: send(Application.get_env(:agent_board, :actions_test_pid), :restart_scheduled)
  end

  setup do
    keys = [:orchestrator_api, :updater, :board_stopper, :actions_test_pid]
    previous = Map.new(keys, &{&1, Application.get_env(:agent_board, &1)})
    Application.put_env(:agent_board, :orchestrator_api, "http://127.0.0.1:1/orchestrator/api")

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:agent_board, key),
          else: Application.put_env(:agent_board, key, value)
      end
    end)

    {:ok, repo} = Board.add_repository("fixture", "actions")

    %{
      repo: repo,
      github:
        Req.new(base_url: "https://api.github.com", plug: {Req.Test, @github}, retry: false),
      orchestrator: Req.merge(Orchestrator.build(), plug: {Req.Test, @orchestrator}),
      owner: Actions.owner(:ui)
    }
  end

  defp task!(repo, number, title \\ "Placar") do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: "queued"
    })
    |> Repo.insert!()
  end

  defp last, do: hd(Actions.recent(1))

  defp no_network do
    Req.Test.stub(@github, fn _conn -> flunk("GitHub must not be called") end)
    Req.Test.stub(@orchestrator, fn _conn -> flunk("the orchestrator must not be called") end)
  end

  defp request(repo, title),
    do: %{
      title: title,
      body: "corpo\n\n@sallaumen-agent",
      key: Board.request_key(repo, "t", [title])
    }

  defp dispatch_params(task, repo) do
    %{
      task: task,
      executor: "claude",
      ceiling_usd: 5.0,
      repository: repo,
      launcher: fn _run_dir -> flunk("the runner must not start") end
    }
  end

  defp superagent!(repo, name) do
    case Superagents.get_by_repository(repo) do
      nil ->
        index = Enum.find_index(@tested, &(&1 == name)) || 0

        {:ok, superagent} =
          Superagents.create(%{
            repository_id: repo.id,
            profile: "superagent-actions-#{name}",
            port: 3300 + index,
            state_dir: "/tmp/actions-superagent-#{name}"
          })

        superagent

      superagent ->
        Repo.preload(superagent, :repository)
    end
  end

  # A params map per red action, for the refusals below.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp red_params(name, %{repo: repo, github: github, orchestrator: orchestrator}) do
    task = task!(repo, 100 + Enum.find_index(@tested, &(&1 == name)))

    case name do
      :create_tasks ->
        %{repository: repo, requests: [request(repo, "Algo")], client: github}

      :ask_task ->
        %{task: task, question: "E aí?", client: github}

      :share_private_context ->
        %{task: task, repository: repo, dir: "issue-#{task.number}", client: github}

      :stop_task ->
        %{task: task, client: github}

      :undo_created_task ->
        %{task: task, client: github}

      :retry_ticket ->
        %{ticket_id: "t1", number: 1, client: orchestrator}

      :auto_retry_ticket ->
        %{ticket_id: "t1", attempt: 1, client: orchestrator}

      :release_task ->
        %{task: task, repository: repo, client: github}

      :dispatch_task ->
        dispatch_params(task, repo)

      :stop_execution ->
        %{
          task: task,
          execution:
            Repo.insert!(%Execution{
              task_id: task.id,
              repository_id: repo.id,
              executor: "claude",
              status: "running",
              run_dir: Path.join(System.tmp_dir!(), "actions-stop-#{task.id}"),
              started_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
            })
        }

      :provision_superagent ->
        {:ok, target} = Board.add_repository("fixture", "provision-target")
        {:ok, source_repo} = Board.add_repository("fixture", "provision-source")

        {:ok, source} =
          Superagents.create(%{
            repository_id: source_repo.id,
            profile: "superagent-provision-source",
            port: 3390,
            state_dir: "/tmp/provision-source"
          })

        %{repository: target, source: source, path: "/tmp/checkout", workers: 2}

      name when name in [:grant_agent_access, :revoke_agent_access] ->
        %{superagent: superagent!(repo, name), login: "convidada", rerun: []}

      name
      when name in [
             :start_superagent,
             :stop_superagent,
             :remove_superagent,
             :retry_provision_superagent
           ] ->
        %{superagent: superagent!(repo, name)}

      :start_agent ->
        %{opts: [starter: fn -> flunk("the agent must not start") end]}

      :forget_conversation ->
        %{}
    end
  end

  describe "the catalog" do
    test "every action has a risk and a test of its own" do
      assert Enum.sort(Actions.names()) == Enum.sort(@tested)

      for %{name: name, risk: risk, does: does} <- Actions.catalog() do
        assert risk in [:green, :yellow, :red], "#{name} has no risk"
        assert does != ""
      end
    end

    test "only the automatic retry and the release hold a standing authorization, both red" do
      assert [
               %{name: :auto_retry_ticket, risk: :red, standing: %{by: "auto_retry"}},
               %{name: :release_task, risk: :red, standing: %{by: "release"}}
             ] = Enum.filter(Actions.catalog(), &Map.has_key?(&1, :standing))
    end

    test "the sentence names the real values", %{repo: repo} do
      task = task!(repo, 12, "Mostrar o volume")

      assert Actions.phrase(:stop_task, %{task: task}) =~
               "Parar a tarefa #12, “Mostrar o volume”?"

      assert Actions.phrase(:create_tasks, %{
               repository: repo,
               requests: [request(repo, "A"), request(repo, "B"), request(repo, "C")]
             }) =~ "Criar no actions 3 tarefas: “A”, “B” e “C”?"

      assert Actions.phrase(:stop_task, %{task: task}, "en-US") =~ "Stop task #12"

      # For Claude Code the issue only gets a label: the sentence says nothing starts.
      claude = Map.put(request(repo, "Placar"), :executor, "claude")

      assert Actions.phrase(:create_tasks, %{repository: repo, requests: [claude]}) ==
               "Criar no actions a tarefa “Placar” para o Claude Code? " <>
                 "O board abre com o rótulo executor:claude; nada começa sozinho."

      long = task!(repo, 13, "Uma issue de teste sem menção para o Claude Code que será fechada")
      assert Actions.phrase(:stop_task, %{task: long}) =~ ~r/“Uma issue de teste[^”]*…”\?/u
    end
  end

  describe "the gate" do
    test "every red action without a confirmation is refused, recorded, and runs nothing",
         context do
      no_network()
      reds = for %{name: name, risk: :red} <- Actions.catalog(), do: name
      assert length(reds) == 19

      for name <- reds do
        params = red_params(name, context)

        assert {:error, {:unconfirmed, phrase}} = Actions.run(name, params, Actions.owner(:api))
        assert phrase == Actions.phrase(name, params)

        assert %Decision{decision: "refused", detail: "unconfirmed", by: "owner", via: "api"} =
                 last()

        assert last().action == Atom.to_string(name)
      end

      assert Repo.aggregate(Task, :count, :id) == 19
      assert Repo.aggregate(Comment, :count, :id) == 0
    end

    test "the sentence is accepted in the language it was shown in", %{repo: repo, owner: owner} do
      no_network()
      task = task!(repo, 8)
      english = Actions.phrase(:archive_task, %{task: task}, "en-US")
      refute english == Actions.phrase(:archive_task, %{task: task})

      assert {:ok, _} = Actions.run(:archive_task, %{task: task}, owner, confirm: english)
      assert Repo.get!(Task, task.id).archived
      # The row keeps the sentence the person read.
      assert %Decision{decision: "confirmed", phrase: ^english} = last()
    end

    test "an English sentence for other values is refused too", %{repo: repo, owner: owner} do
      no_network()
      task = task!(repo, 9)
      old = Actions.phrase(:stop_task, %{task: task}, "en-US")
      renamed = task |> Ecto.Changeset.change(title: "Other") |> Repo.update!()

      assert {:error, {:phrase_changed, _}} =
               Actions.run(:stop_task, %{task: renamed}, owner, confirm: old)

      refute Repo.get!(Task, task.id).stopped
    end

    test "every sentence a button shows exists in English", %{repo: repo} do
      task = task!(repo, 10) |> Repo.preload(:repository)

      for {name, params} <- [
            {:dispatch_task, %{task: task, executor: "claude", repository: repo}},
            {:retry_ticket, %{ticket_id: "t", number: 10}},
            {:start_agent, %{}},
            {:resume_task, %{task: task}}
          ] do
        refute Actions.phrase(name, params, "en-US") == Actions.phrase(name, params, "pt-BR")
      end
    end

    test "a sentence for other values is refused", %{repo: repo, owner: owner} do
      no_network()
      task = task!(repo, 7)
      old = Actions.phrase(:stop_task, %{task: task})
      renamed = task |> Ecto.Changeset.change(title: "Outro") |> Repo.update!()

      assert {:error, {:phrase_changed, new}} =
               Actions.run(:stop_task, %{task: renamed}, owner, confirm: old)

      assert new =~ "“Outro”"
      refute Repo.get!(Task, task.id).stopped
      assert %Decision{decision: "refused", detail: "phrase_changed"} = last()
    end

    test "a blank confirmation is no confirmation", %{repo: repo, owner: owner} do
      no_network()
      task = task!(repo, 8)

      assert {:error, {:unconfirmed, _}} =
               Actions.run(:stop_task, %{task: task}, owner, confirm: "")
    end

    test "the standing authorization covers only its own actor", context do
      no_network()
      params = red_params(:auto_retry_ticket, context)

      assert {:error, {:unconfirmed, _}} =
               Actions.run(:auto_retry_ticket, params, Actions.system("sync"))

      assert {:error, {:unconfirmed, _}} =
               Actions.run(:retry_ticket, %{ticket_id: "t1"}, Actions.system("auto_retry"))
    end

    test "the owner's own words confirm only the actions that take them", %{repo: repo} do
      no_network()
      voice = Actions.owner(:voice)
      params = %{repository: repo, requests: [request(repo, "Algo")]}

      assert {:error, {:unconfirmed, _}} =
               Actions.run(:create_tasks, params, voice, confirm: {:words, "cria isso aí"})

      assert {:error, {:unconfirmed, _}} =
               Actions.run(:stop_task, %{task: task!(repo, 9)}, voice,
                 confirm: {:words, "desfaz"}
               )

      assert Actions.direct_order?(:create_tasks, "Já cria direto: corrigir o botão")
      assert Actions.direct_order?(:create_tasks, "create it right away")
      refute Actions.direct_order?(:create_tasks, "cria uma tarefa")
      assert Actions.direct_order?(:undo_created_task, "pode desfazer aquela")
      refute Actions.direct_order?(:stop_task, "desfaz")
    end

    test "a no is recorded as the owner's refusal", %{repo: repo, owner: owner} do
      task = task!(repo, 11)

      assert :ok = Actions.decline(:stop_task, %{task: task}, owner)

      assert %Decision{decision: "refused", detail: "declined", by: "owner", via: "ui"} =
               d = last()

      assert d.phrase == Actions.phrase(:stop_task, %{task: task})
      assert d.subject == "#11" and d.repository_id == repo.id
    end

    test "an executed decision is written before the effect runs", %{repo: repo, github: github} do
      task = task!(repo, 13)
      test_pid = self()

      Req.Test.stub(@github, fn conn ->
        send(test_pid, {:during, Repo.all(Decision)})
        Req.Test.json(conn, %{"state" => "closed"})
      end)

      phrase = Actions.phrase(:stop_task, %{task: task})

      {:ok, _} =
        Actions.run(:stop_task, %{task: task, client: github}, Actions.owner(:ui),
          confirm: phrase
        )

      assert_received {:during, [%Decision{decision: "confirmed", outcome: nil}]}
      assert %Decision{outcome: "ok"} = last()
    end
  end

  describe "each action" do
    test "create_tasks opens the issues, once, after the confirmation", %{repo: repo} = c do
      Req.Test.stub(@github, fn conn ->
        Req.Test.json(conn, %{"number" => 40, "html_url" => "https://github.com/x/y/issues/40"})
      end)

      params = %{repository: repo, requests: [request(repo, "Placar novo")], client: c.github}
      phrase = Actions.phrase(:create_tasks, params)

      assert {:ok, [{_request, {:ok, %Task{number: 40}, :created}}]} =
               Actions.run(:create_tasks, params, c.owner, confirm: phrase)

      assert %Decision{action: "create_tasks", risk: "red", decision: "confirmed"} = d = last()
      assert d.evidence == "phrase" and d.outcome == "ok" and d.repository_id == repo.id
      assert d.subject == "fixture/actions (1)"
    end

    test "create_tasks by the owner's words (cria direto)", %{repo: repo} = c do
      Req.Test.stub(@github, fn conn ->
        Req.Test.json(conn, %{"number" => 41, "html_url" => "https://github.com/x/y/issues/41"})
      end)

      params = %{repository: repo, requests: [request(repo, "Botão")], client: c.github}
      words = {:words, "cria direto: botão"}

      assert {:ok, [{_, {:ok, _task, :created}}]} =
               Actions.run(:create_tasks, params, Actions.owner(:voice), confirm: words)

      assert %Decision{decision: "confirmed", evidence: "words", words: "cria direto: botão"} =
               last()
    end

    test "ask_task posts the comment after the confirmation", %{repo: repo} = c do
      task = task!(repo, 20)
      Req.Test.stub(@github, &Req.Test.json(&1, %{"id" => 77, "user" => %{"login" => "me"}}))
      params = %{task: task, question: "Rodou os testes?", client: c.github}

      assert {:ok, _} =
               Actions.run(:ask_task, params, c.owner, confirm: Actions.phrase(:ask_task, params))

      assert %Comment{github_id: 77} = Repo.get_by!(Comment, task_id: task.id)
      assert %Decision{action: "ask_task", decision: "confirmed", outcome: "ok"} = last()
    end

    test "share_private_context comments the path only, without the mention", %{repo: repo} = c do
      task = task!(repo, 21)
      test_pid = self()

      Req.Test.stub(@github, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:comment, conn.request_path, Jason.decode!(raw)["body"]})
        Req.Test.json(conn, %{"id" => 78})
      end)

      params = %{task: task, repository: repo, dir: "issue-21", client: c.github}
      phrase = Actions.phrase(:share_private_context, params)
      assert phrase =~ "issue-21"

      assert {:error, {:unconfirmed, _}} = Actions.run(:share_private_context, params, c.owner)
      refute_received {:comment, _, _}

      assert {:ok, _text} = Actions.run(:share_private_context, params, c.owner, confirm: phrase)
      assert_received {:comment, path, body}
      assert path =~ "/issues/21/comments"
      assert body =~ "<!-- agent-board:private issue-21 -->"
      assert body =~ PrivateContext.path(repo, "issue-21")
      refute body =~ "@sallaumen-agent"
      assert %Decision{action: "share_private_context", outcome: "ok"} = last()
    end

    test "stop_execution stops the active row after the confirmation", %{repo: repo} do
      task = task!(repo, 23)
      run_dir = Path.join(System.tmp_dir!(), "actions-stop-ok-#{task.id}")
      on_exit(fn -> File.rm_rf(run_dir) end)
      File.mkdir_p!(run_dir)
      File.write!(Path.join(run_dir, "status"), "running")

      execution =
        Repo.insert!(%Execution{
          task_id: task.id,
          repository_id: repo.id,
          executor: "claude",
          status: "running",
          run_dir: run_dir,
          started_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })

      previous = Application.get_env(:agent_board, :tmux_killer)
      Application.put_env(:agent_board, :tmux_killer, fn _session -> :ok end)
      on_exit(fn -> Application.put_env(:agent_board, :tmux_killer, previous) end)

      params = %{task: task, execution: execution}
      phrase = Actions.phrase(:stop_execution, params)

      assert {:ok, text} =
               Actions.run(:stop_execution, params, Actions.owner(:ui), confirm: phrase)

      assert text =~ "Execução parada"
      assert Repo.get!(Execution, execution.id).status == "stopped"
      assert Repo.get!(Task, task.id).state == "blocked"
      assert %Decision{action: "stop_execution", outcome: "ok"} = last()
    end

    test "provision_superagent creates the row after the confirmation", _context do
      {:ok, target} = Board.add_repository("fixture", "provision-action")
      {:ok, source_repo} = Board.add_repository("fixture", "provision-action-source")

      {:ok, source} =
        Superagents.create(%{
          repository_id: source_repo.id,
          profile: "superagent-provision-action-source",
          port: 3391,
          state_dir: "/tmp/provision-action-source"
        })

      previous = Application.get_env(:agent_board, :superagent_provisioner)
      Application.put_env(:agent_board, :superagent_provisioner, FakeProvisioner)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:agent_board, :superagent_provisioner, previous),
          else: Application.delete_env(:agent_board, :superagent_provisioner)
      end)

      params = %{repository: target, source: source, path: "/tmp/checkout", workers: 2}
      phrase = Actions.phrase(:provision_superagent, params)

      assert {:ok, text} =
               Actions.run(:provision_superagent, params, Actions.owner(:ui), confirm: phrase)

      assert text =~ "reservado"
      assert superagent = Superagents.get_by_repository(target)
      assert superagent.max_workers == 2
      assert %Decision{action: "provision_superagent", outcome: "ok"} = last()
    end

    test "remove_superagent archives the row and its state", _context do
      {:ok, pid} = FakeManager.start()
      root = Path.join(System.tmp_dir!(), "archive-actions-#{System.unique_integer([:positive])}")
      state = Path.join(root, "state")
      File.mkdir_p!(state)
      previous = Application.get_env(:agent_board, :superagent_manager)
      previous_root = Application.get_env(:agent_board, :superagent_archive_root)
      Application.put_env(:agent_board, :superagent_manager, FakeManager)
      Application.put_env(:agent_board, :superagent_archive_root, Path.join(root, "archive"))

      on_exit(fn ->
        if previous,
          do: Application.put_env(:agent_board, :superagent_manager, previous),
          else: Application.delete_env(:agent_board, :superagent_manager)

        if previous_root,
          do: Application.put_env(:agent_board, :superagent_archive_root, previous_root),
          else: Application.delete_env(:agent_board, :superagent_archive_root)

        if Process.alive?(pid), do: Agent.stop(pid)
        File.rm_rf!(root)
      end)

      {:ok, source_repo} = Board.add_repository("fixture", "remove-source")

      {:ok, superagent} =
        Superagents.create(%{
          repository_id: source_repo.id,
          profile: "superagent-remove-action",
          port: 3392,
          state_dir: state
        })

      FakeManager.put(superagent.id, %{state: "ready"})
      phrase = Actions.phrase(:remove_superagent, %{superagent: superagent})

      assert {:ok, text} =
               Actions.run(:remove_superagent, %{superagent: superagent}, Actions.owner(:ui),
                 confirm: phrase
               )

      assert text =~ "arquivados"
      refute Superagents.get_by_repository(source_repo)
    end

    test "superagent start, stop, pause, resume and scale are actions", %{repo: repo} do
      {:ok, pid} = FakeManager.start()
      previous = Application.get_env(:agent_board, :superagent_manager)
      Application.put_env(:agent_board, :superagent_manager, FakeManager)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:agent_board, :superagent_manager, previous),
          else: Application.delete_env(:agent_board, :superagent_manager)

        if Process.alive?(pid), do: Agent.stop(pid)
      end)

      superagent = superagent!(repo, :start_superagent)

      assert {:ok, _} =
               Actions.run(:start_superagent, %{superagent: superagent}, Actions.owner(:ui),
                 confirm: Actions.phrase(:start_superagent, %{superagent: superagent})
               )

      assert Repo.get!(Superagents.Superagent, superagent.id).desired_state == "running"

      assert {:ok, _} =
               Actions.run(:pause_superagent, %{superagent: superagent}, Actions.owner(:ui))

      assert Repo.get!(Superagents.Superagent, superagent.id).desired_state == "paused"

      assert {:ok, _} =
               Actions.run(:resume_superagent, %{superagent: superagent}, Actions.owner(:ui))

      assert {:ok, _} =
               Actions.run(
                 :scale_superagent,
                 %{superagent: superagent, workers: 5},
                 Actions.owner(:ui)
               )

      assert Repo.get!(Superagents.Superagent, superagent.id).max_workers == 5

      assert {:ok, _} =
               Actions.run(:stop_superagent, %{superagent: superagent}, Actions.owner(:ui),
                 confirm: Actions.phrase(:stop_superagent, %{superagent: superagent})
               )

      assert Repo.get!(Superagents.Superagent, superagent.id).desired_state == "stopped"
    end

    test "stop_task closes the issue after the confirmation", %{repo: repo} = c do
      task = task!(repo, 21)
      Req.Test.stub(@github, &Req.Test.json(&1, %{"state" => "closed"}))
      params = %{task: task, client: c.github}

      assert {:ok, %Task{stopped: true}} =
               Actions.run(:stop_task, params, c.owner,
                 confirm: Actions.phrase(:stop_task, params)
               )

      assert %Decision{action: "stop_task", decision: "confirmed", outcome: "ok"} = last()
    end

    test "undo_created_task closes on the word desfaz", %{repo: repo} = c do
      task = task!(repo, 22)
      Req.Test.stub(@github, &Req.Test.json(&1, %{"state" => "closed"}))

      params = %{task: task, client: c.github}
      voice = Actions.owner(:voice)

      assert {:ok, %Task{stopped: true}} =
               Actions.run(:undo_created_task, params, voice, confirm: {:words, "desfaz"})

      assert %Decision{action: "undo_created_task", evidence: "words", via: "voice"} = last()
    end

    test "archive_task is yellow and runs without a question", %{repo: repo, owner: owner} do
      task = task!(repo, 23)

      assert {:ok, %Task{archived: true}} = Actions.run(:archive_task, %{task: task}, owner)

      assert %Decision{action: "archive_task", risk: "yellow", decision: "automatic"} = d = last()
      assert is_nil(d.evidence) and d.outcome == "ok"
    end

    test "resume_task is yellow and runs without a question", %{repo: repo, owner: owner} do
      {:ok, task} = repo |> task!(24) |> Board.archive_task()

      assert {:ok, %Task{archived: false, state: "queued"}} =
               Actions.run(:resume_task, %{task: task}, owner)

      assert %Decision{action: "resume_task", decision: "automatic", outcome: "ok"} = last()
    end

    test "retry_ticket asks the runner after the confirmation", %{repo: repo} = c do
      Req.Test.stub(@orchestrator, fn conn ->
        assert conn.request_path == "/orchestrator/api/tickets/t9/retry"
        Req.Test.json(conn, %{"retried" => true})
      end)

      params = %{ticket_id: "t9", repository_id: repo.id, number: 9, client: c.orchestrator}
      phrase = Actions.phrase(:retry_ticket, params)
      assert phrase =~ "Pedir ao agente uma nova tentativa de #9 agora?"

      assert {:ok, "Nova tentativa pedida" <> _} =
               Actions.run(:retry_ticket, params, c.owner, confirm: phrase)

      assert %Decision{action: "retry_ticket", subject: "ticket t9 #9", outcome: "ok"} = last()
    end

    test "auto_retry_ticket runs on the standing authorization, by auto_retry", c do
      Req.Test.stub(@orchestrator, &Req.Test.json(&1, %{"retried" => true}))
      params = %{ticket_id: "t5", attempt: 2, client: c.orchestrator}

      assert {:ok, :retried} =
               Actions.run(:auto_retry_ticket, params, Actions.system("auto_retry"))

      assert %Decision{decision: "automatic", evidence: "standing", by: "auto_retry"} = d = last()
      assert d.via == "system" and d.phrase =~ "(2 de 3)"
    end

    test "the result is written in the language of the confirmation", %{owner: owner} do
      params = %{opts: [starter: fn -> {"ok", 0} end]}

      assert {:ok, "The agent is up."} =
               Actions.run(:start_agent, params, owner,
                 confirm: Actions.phrase(:start_agent, %{}, "en-US")
               )

      assert {:ok, "O agente está de pé."} =
               Actions.run(:start_agent, params, owner,
                 confirm: Actions.phrase(:start_agent, %{}, "pt-BR")
               )

      # Naming the language works too, for an action that asks nothing.
      assert {:ok, "The agent is up."} =
               Actions.run(:start_agent, params, owner,
                 confirm: Actions.phrase(:start_agent, %{}, "en-US"),
                 language: "en-US"
               )
    end

    test "a superagent command answers in the language of its confirmation",
         %{repo: repo, owner: owner} do
      {:ok, pid} = FakeManager.start()
      previous = Application.get_env(:agent_board, :superagent_manager)
      Application.put_env(:agent_board, :superagent_manager, FakeManager)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:agent_board, :superagent_manager, previous),
          else: Application.delete_env(:agent_board, :superagent_manager)

        if Process.alive?(pid), do: Agent.stop(pid)
      end)

      params = %{superagent: superagent!(repo, :start_superagent)}

      assert {:ok, "Superagent started. The status updates on the next read."} =
               Actions.run(:start_superagent, params, owner,
                 confirm: Actions.phrase(:start_superagent, params, "en-US")
               )

      assert {:ok, "Superagent stopped."} =
               Actions.run(:stop_superagent, params, owner,
                 confirm: Actions.phrase(:stop_superagent, params, "en-US")
               )

      assert {:ok, "Superagent parado."} =
               Actions.run(:stop_superagent, params, owner,
                 confirm: Actions.phrase(:stop_superagent, params, "pt-BR")
               )

      # A yellow action asks nothing: the door names the language, or the
      # answer is Portuguese as before.
      assert {:ok, "Superagent paused."} =
               Actions.run(:pause_superagent, params, owner, language: "en-US")

      assert {:ok, "Superagent retomado."} = Actions.run(:resume_superagent, params, owner)
    end

    test "a refused dispatch and a refused grant say why in the language of the confirmation",
         %{repo: repo, owner: owner} do
      no_network()
      dispatch = dispatch_params(task!(repo, 61), repo)

      assert {:error,
              "The task belongs to another executor; choose the executor on the task before dispatching"} =
               Actions.run(:dispatch_task, dispatch, owner,
                 confirm: Actions.phrase(:dispatch_task, dispatch, "en-US")
               )

      assert {:error,
              "a tarefa é de outro executor; escolha o executor na tarefa antes de despachar"} =
               Actions.run(:dispatch_task, dispatch, owner,
                 confirm: Actions.phrase(:dispatch_task, dispatch, "pt-BR")
               )

      grant = %{superagent: superagent!(repo, :grant_agent_access), login: "sem login", rerun: []}

      assert {:error, "Could not allow @sem login: that GitHub login is not valid."} =
               Actions.run(:grant_agent_access, grant, owner,
                 confirm: Actions.phrase(:grant_agent_access, grant, "en-US")
               )

      assert {:error, "Não foi possível liberar @sem login: esse login do GitHub não é válido."} =
               Actions.run(:grant_agent_access, grant, owner,
                 confirm: Actions.phrase(:grant_agent_access, grant, "pt-BR")
               )
    end

    test "a health check that gives up is a slow boot, not a failed one", %{owner: owner} do
      params = %{opts: [starter: fn -> {"Startup health check timed out after 60s", 1} end]}

      assert {:ok, text} =
               Actions.run(:start_agent, params, owner,
                 confirm: Actions.phrase(:start_agent, %{})
               )

      assert text =~ "ainda não respondeu"
    end

    test "start_agent runs the manager after the confirmation", %{owner: owner} do
      test_pid = self()
      params = %{opts: [starter: fn -> send(test_pid, :started) && {"ok", 0} end]}

      assert {:ok, "O agente está de pé."} =
               Actions.run(:start_agent, params, owner,
                 confirm: Actions.phrase(:start_agent, %{})
               )

      assert_received :started
      assert %Decision{action: "start_agent", decision: "confirmed", outcome: "ok"} = last()
    end

    test "set_max_workers is yellow and saves the ceiling", %{orchestrator: client, owner: owner} do
      executor = %{"maxWorkers" => 3, "model" => %{}}

      Req.Test.stub(@orchestrator, fn
        %{method: "GET"} = conn ->
          Req.Test.json(conn, %{
            "blocks" => %{"executor" => %{"value" => executor, "revision" => 1}}
          })

        %{method: "PUT"} = conn ->
          Req.Test.json(conn, %{"saved" => true, "revision" => 2, "restarting" => false})
      end)

      assert {:ok, 4} = Actions.run(:set_max_workers, %{max: 4, client: client}, owner)

      assert %Decision{action: "set_max_workers", decision: "automatic", subject: "maxWorkers=4"} =
               last()
    end

    test "add_repository is yellow and tracks the repository", %{owner: owner} do
      assert {:ok, _} = Actions.run(:add_repository, %{owner: "fixture", name: "novo"}, owner)
      assert Board.repository_by_slug("fixture/novo")
      assert %Decision{action: "add_repository", subject: "fixture/novo", outcome: "ok"} = last()
    end

    test "change_setting saves a voice preference, and an unknown one is an error", %{
      owner: owner
    } do
      assert :ok = Actions.run(:change_setting, %{setting: "volume", value: 40}, owner)
      assert Voice.volume() == 40
      assert %Decision{action: "change_setting", subject: "volume", outcome: "ok"} = last()

      assert :ok = Actions.run(:change_setting, %{setting: "tts_model", value: "m1"}, owner)
      assert Settings.get("elevenlabs_tts_model") == "m1"

      assert {:error, :unknown_setting} =
               Actions.run(:change_setting, %{setting: "nada", value: 1}, owner)

      assert %Decision{outcome: "error", detail: ":unknown_setting"} = last()
    end

    test "change_setting saves the daily summary form; a bad hour saves nothing", %{owner: owner} do
      form = %{"enabled" => "true", "at" => "07:30"}

      assert :ok = Actions.run(:change_setting, %{setting: "daily_summary", value: form}, owner)
      assert AgentBoard.DailySummary.settings().at == ~T[07:30:00]

      bad = %{setting: "daily_summary", value: %{"at" => "25:99"}}
      assert {:error, :invalid_time} = Actions.run(:change_setting, bad, owner)
      assert %Decision{subject: "daily_summary", outcome: "error"} = last()
    end

    test "dismiss_summary is yellow and hides the day's summary", %{owner: owner} do
      assert Actions.run(:dismiss_summary, %{id: -1}, owner)

      assert %Decision{action: "dismiss_summary", risk: "yellow", decision: "automatic"} =
               d = last()

      assert d.subject == "daily_summary -1"
    end

    test "forget_conversation clears the memory after the confirmation", %{owner: owner} do
      {:ok, _} = Conversation.record("owner", "lembra disso")
      phrase = Actions.phrase(:forget_conversation, %{})

      assert :ok = Actions.run(:forget_conversation, %{}, owner, confirm: phrase)
      assert Conversation.recent() == []
      assert %Decision{action: "forget_conversation", decision: "confirmed"} = last()
    end

    test "sync_now is green and queues a sync", %{owner: owner} do
      assert {:ok, %Oban.Job{worker: "AgentBoard.Sync.Worker"}} =
               Actions.run(:sync_now, %{}, owner)

      assert %Decision{action: "sync_now", risk: "green", decision: "automatic"} = last()
    end

    test "update_board fast-forwards through the updater", %{owner: owner} do
      Application.put_env(:agent_board, :updater, UpdaterStub)

      assert {:ok, "abc1234"} = Actions.run(:update_board, %{}, owner)
      assert %Decision{action: "update_board", risk: "yellow", outcome: "ok"} = last()
    end

    test "restart_board schedules the restart and stops this VM", %{owner: owner} do
      test_pid = self()
      Application.put_env(:agent_board, :updater, UpdaterStub)
      Application.put_env(:agent_board, :actions_test_pid, test_pid)
      Application.put_env(:agent_board, :board_stopper, fn -> send(test_pid, :stopped) end)

      assert :ok = Actions.run(:restart_board, %{}, owner)
      assert_received :restart_scheduled
      assert_received :stopped
      assert %Decision{action: "restart_board", outcome: "ok"} = last()
    end
  end

  describe "no write outside the registry" do
    # The effects of the registered actions. Each may be called only from
    # `lib/agent_board/actions.ex`, plus the module that owns the store.
    @effects [
      {~r/\bBoard\.Requests\.(create_task|create_request)\(/, []},
      {~r/\bBoard\.(stop_task|archive_task|resume_task|ask|add_repository|delete_repository)\(/,
       []},
      {~r/\bGitHub\.(create_issue|close_issue|create_comment)\(/,
       [
         "lib/agent_board/board.ex",
         "lib/agent_board/board/requests.ex",
         "lib/agent_board/board/split_graph.ex",
         "lib/agent_board/release.ex"
       ]},
      # AgentControl.retry is the owner's retry, itself reachable only from here.
      {~r/\bOrchestrator\.(retry|set_max_workers)\(/, ["lib/agent_board/agent_control.ex"]},
      {~r/\bAgentControl\.(retry|start_agent)\(/, []},
      {~r/\bRunners\.dispatch\(/, []},
      {~r/\bSuperagents\.retry_provision\(/, []},
      {~r/\bAgentAccess\.(grant|revoke|dismiss)\(/, []},
      {~r/\b(Voice\.put_\w+|ElevenLabs\.save_voice)\(/, []},
      {~r/\bSettings\.put\(/,
       [
         "lib/agent_board/voice.ex",
         "lib/agent_board/eleven_labs.ex",
         "lib/agent_board/daily_summary.ex"
       ]},
      {~r/\bDailySummary\.(put_settings|dismiss)\(/, []},
      {~r/\bConversation\.clear\(/, []},
      {~r/\bOban\.insert/, []},
      {~r/\bupdater\(\)\.(pull|restart)\(/, []},
      {~r/\bSystem\.stop\b/, []}
    ]

    test "lib/ calls a write only through AgentBoard.Actions" do
      offenders =
        for path <- Path.wildcard("lib/**/*.ex"),
            path != "lib/agent_board/actions.ex",
            {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
            not String.starts_with?(String.trim_leading(line), "#"),
            {pattern, allowed} <- @effects,
            path not in allowed,
            Regex.match?(pattern, line),
            do: "#{path}:#{number}: #{String.trim(line)}"

      assert offenders == [], "writes outside AgentBoard.Actions:\n" <> Enum.join(offenders, "\n")
    end
  end

  test "a repository name past the column is refused, with its decision recorded" do
    name = String.duplicate("r", 300)

    assert {:error, %Ecto.Changeset{}} =
             Actions.run(:add_repository, %{owner: "fixture", name: name}, Actions.owner(:ui))

    assert %Decision{action: "add_repository", outcome: "error", subject: subject} =
             Repo.one(from d in Decision, order_by: [desc: d.id], limit: 1)

    assert String.length(subject) == 255
  end
end
