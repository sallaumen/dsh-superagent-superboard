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
    refute Runners.active_for_task?(task.id)
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
  end
end
