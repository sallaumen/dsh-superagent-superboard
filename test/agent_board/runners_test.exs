defmodule AgentBoard.RunnersTest do
  @moduledoc "O despacho local: pausa, orçamento, uma execução por tarefa e a observação do resultado."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Repo, Runners, Settings}
  alias AgentBoard.Board.Task

  setup do
    root = Path.join(System.tmp_dir!(), "runners-#{System.unique_integer([:positive])}")
    repo_dir = Path.join(root, "arena")
    File.mkdir_p!(repo_dir)
    File.mkdir_p!(Path.join(root, "runs"))

    previous = Application.get_env(:agent_board, :runner_root)
    Application.put_env(:agent_board, :runner_root, Path.join(root, "runs"))

    on_exit(fn ->
      File.rm_rf!(root)

      if previous,
        do: Application.put_env(:agent_board, :runner_root, previous),
        else: Application.delete_env(:agent_board, :runner_root)
    end)

    {:ok, repository} = Board.add_repository("fixture", "arena")
    :ok = Settings.put("dispatch_repo_path:fixture/arena", repo_dir)
    :ok = Settings.put("dispatch_paused", "false")
    :ok = Settings.put("dispatch_monthly_usd", "300")
    :ok = Settings.put("dispatch_task_usd", "5")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repository.id,
        kind: "issue",
        number: 42,
        title: "Ajustar o volume",
        body: "O volume do ataque está baixo.",
        state: "queued",
        executor: "claude"
      })
      |> Repo.insert!()
      |> Repo.preload(:repository)

    %{repository: repository, task: task, root: root, repo_dir: repo_dir}
  end

  defp launcher(test_pid) do
    fn run_dir ->
      send(test_pid, {:launched, run_dir})
      File.write!(Path.join(run_dir, "status"), "running")
      :ok
    end
  end

  test "dispatch writes the run and claims one execution per task", %{task: task} do
    test_pid = self()

    assert {:ok, execution} = Runners.dispatch(task, "claude", launcher: launcher(test_pid))

    assert execution.status == "starting"
    assert execution.executor == "claude"
    assert execution.session_id =~ ~r/^[0-9a-f-]{36}$/
    assert File.exists?(Path.join(execution.run_dir, "prompt.md"))
    assert File.exists?(Path.join(execution.run_dir, "launch.sh"))
    assert File.read!(Path.join(execution.run_dir, "launch.sh")) =~ "PROMPT_FILE="
    assert_received {:launched, run_dir}
    assert run_dir == execution.run_dir

    assert Runners.active_for_task?(task.id)

    assert {:error, :already_running} =
             Runners.dispatch(task, "claude", launcher: launcher(test_pid))
  end

  test "a missing executor binary refuses before starting", %{task: task} do
    previous = Application.get_env(:agent_board, :claude_bin)
    Application.put_env(:agent_board, :claude_bin, "/definitely/not/claude")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :claude_bin, previous),
        else: Application.delete_env(:agent_board, :claude_bin)
    end)

    assert {:error, :runner_missing} = Runners.check(task, "claude")
  end

  test "pause, monthly cap and the Codex reserve stop a new execution", %{task: task} do
    :ok = Settings.put("dispatch_paused", "true")
    assert {:error, :paused} = Runners.check(task, "claude")
    :ok = Settings.put("dispatch_paused", "false")

    :ok = Settings.put("dispatch_monthly_usd", "0")
    assert {:error, :monthly_budget} = Runners.check(task, "claude")
    :ok = Settings.put("dispatch_monthly_usd", "300")

    Repo.insert_all("usage_limits", [
      %{
        source: "codex",
        limit_id: "codex",
        primary_used_percent: 90.0,
        primary_window_minutes: 10_080,
        observed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])

    :ok = Settings.put("dispatch_reserve_percent", "50")
    assert {:error, :quota_reserved} = Runners.check(task, "codex")
    :ok = Settings.put("dispatch_reserve_percent", "0")
    assert {:ok, %{timeout_seconds: 1800}} = Runners.check(task, "codex")
    assert {:ok, %{timeout_seconds: 7200}} = Runners.check(task, "claude")
  end

  test "the confirmed action is the only door, and it records the decision", %{task: task} do
    test_pid = self()

    params = %{
      task: task,
      executor: "claude",
      ceiling_usd: 5.0,
      repository: task.repository,
      launcher: launcher(test_pid)
    }

    phrase = AgentBoard.Actions.phrase(:dispatch_task, params)

    assert {:error, {:unconfirmed, ^phrase}} =
             AgentBoard.Actions.run(:dispatch_task, params, AgentBoard.Actions.owner(:ui))

    assert %AgentBoard.Actions.Decision{
             action: "dispatch_task",
             decision: "refused",
             detail: "unconfirmed"
           } = hd(AgentBoard.Actions.recent(1))

    assert {:ok, text} =
             AgentBoard.Actions.run(:dispatch_task, params, AgentBoard.Actions.owner(:ui),
               confirm: phrase
             )

    assert text =~ "Despacho iniciado"
    assert Runners.active_for_task?(task.id)

    assert %AgentBoard.Actions.Decision{action: "dispatch_task", decision: "confirmed"} =
             hd(AgentBoard.Actions.recent(1))
  end

  test "running executions appear in the Today list with their executor", %{task: task} do
    test_pid = self()
    {:ok, execution} = Runners.dispatch(task, "claude", launcher: launcher(test_pid))
    assert_received {:launched, _run_dir}

    assert [item] = Runners.running_items()
    assert item.id == task.id
    assert item.repo == "fixture/arena"
    assert item.executor == "claude"
    assert item.executor_name == "Claude Code"
    refute is_nil(item.at)
    assert execution.status == "starting"
  end

  test "fallback classifies quota, network and content without starting anything" do
    claude = %AgentBoard.Runners.Execution{
      status: "failed",
      executor: "claude",
      error: "429 quota exhausted"
    }

    network = %AgentBoard.Runners.Execution{
      status: "failed",
      executor: "claude",
      error: "dial tcp: connection refused"
    }

    content = %AgentBoard.Runners.Execution{
      status: "failed",
      executor: "claude",
      error: "2 testes falharam"
    }

    assert %{kind: :switch, executor: "codex", reason: reason} = Runners.fallback(claude)
    assert reason =~ "cota ou login"

    assert %{kind: :retry, executor: "claude"} = Runners.fallback(network)
    assert Runners.fallback(content) == :none
    assert Runners.fallback(nil) == :none
  end

  test "a confirmed switch changes the task's executor before it starts", %{task: task} do
    test_pid = self()

    assert {:ok, execution} =
             Runners.dispatch(task, "codex",
               allow_switch: true,
               ceiling_usd: nil,
               launcher: launcher(test_pid)
             )

    assert execution.executor == "codex"
    assert Repo.get!(Task, task.id).executor == "codex"
  end

  test "tick reads the runner's status and result", %{task: task} do
    test_pid = self()
    {:ok, execution} = Runners.dispatch(task, "claude", launcher: launcher(test_pid))
    assert_received {:launched, run_dir}

    File.write!(Path.join(run_dir, "status"), "done")
    File.write!(Path.join(run_dir, "session_id"), "session-1")
    File.write!(Path.join(run_dir, "result"), "PR #9 mesclado")

    assert :ok = Runners.tick()

    execution = Repo.get!(AgentBoard.Runners.Execution, execution.id)
    assert execution.status == "done"
    assert execution.session_id == "session-1"
    assert execution.result == "PR #9 mesclado"
    assert Repo.get!(Task, task.id).state == "ready"
    refute Runners.active_for_task?(task.id)
  end

  test "a runner that never writes a status is failed by the watchdog", %{task: task} do
    launcher = fn _run_dir -> :ok end
    {:ok, execution} = Runners.dispatch(task, "claude", launcher: launcher)

    Repo.update_all(
      from(e in AgentBoard.Runners.Execution, where: e.id == ^execution.id),
      set: [started_at: DateTime.add(DateTime.utc_now(), -10_000, :second)]
    )

    Runners.tick()

    execution = Repo.get!(AgentBoard.Runners.Execution, execution.id)
    assert execution.status == "failed"
    assert execution.error =~ "não escreveu o estado a tempo"
  end

  test "a runner that fails records the error", %{task: task} do
    test_pid = self()
    {:ok, execution} = Runners.dispatch(task, "claude", launcher: launcher(test_pid))
    assert_received {:launched, run_dir}

    File.write!(Path.join(run_dir, "status"), "failed")
    File.write!(Path.join(run_dir, "error"), "claude: sem login")

    Runners.tick()

    execution = Repo.get!(AgentBoard.Runners.Execution, execution.id)
    assert execution.status == "failed"
    assert execution.error == "claude: sem login"
    assert Repo.get!(Task, task.id).state == "blocked"
  end
end
