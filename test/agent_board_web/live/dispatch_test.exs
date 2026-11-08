defmodule AgentBoardWeb.DispatchTest do
  @moduledoc "O despacho na tela: a frase primeiro, o runner só depois do sim, e a pausa global."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo, Runners, Settings}
  alias AgentBoard.Board.Task

  setup do
    root = Path.join(System.tmp_dir!(), "dispatch-ui-#{System.unique_integer([:positive])}")
    repo_dir = Path.join(root, "arena")
    File.mkdir_p!(repo_dir)
    File.mkdir_p!(Path.join(root, "runs"))

    previous = Application.get_env(:agent_board, :runner_root)

    previous_bins =
      Map.new([:claude_bin, :codex_bin], &{&1, Application.get_env(:agent_board, &1)})

    previous_tmux = Application.get_env(:agent_board, :tmux_killer)
    Application.put_env(:agent_board, :tmux_killer, fn _session -> :ok end)

    test_pid = self()
    fake_bin = Path.join(root, "fake-bin")
    File.write!(fake_bin, "#!/bin/sh\nexit 0\n")
    File.chmod!(fake_bin, 0o755)
    Application.put_env(:agent_board, :claude_bin, fake_bin)
    Application.put_env(:agent_board, :codex_bin, fake_bin)

    Application.put_env(:agent_board, :runner_root, Path.join(root, "runs"))

    Application.put_env(:agent_board, :runner_launcher, fn run_dir ->
      send(test_pid, {:launched, run_dir})
      File.write!(Path.join(run_dir, "status"), "running")
      :ok
    end)

    on_exit(fn ->
      File.rm_rf!(root)

      if previous,
        do: Application.put_env(:agent_board, :runner_root, previous),
        else: Application.delete_env(:agent_board, :runner_root)

      for {key, value} <- previous_bins do
        if value,
          do: Application.put_env(:agent_board, key, value),
          else: Application.delete_env(:agent_board, key)
      end

      if previous_tmux,
        do: Application.put_env(:agent_board, :tmux_killer, previous_tmux),
        else: Application.delete_env(:agent_board, :tmux_killer)

      Application.delete_env(:agent_board, :runner_launcher)
    end)

    {:ok, repo} = Board.add_repository("fixture", "dispatch")
    :ok = Settings.put("dispatch_repo_path:fixture/dispatch", repo_dir)
    :ok = Settings.put("dispatch_paused", "false")
    :ok = Settings.put("dispatch_task_usd", "5")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 42,
        title: "Ajustar o volume",
        body: "O volume do ataque está baixo.",
        state: "queued",
        executor: "claude"
      })
      |> Repo.insert!()

    %{repo: repo, task: task}
  end

  test "the sentence comes first and the runner starts only after the sim", %{
    conn: conn,
    task: task
  } do
    {:ok, view, _html} =
      live(conn, "/?repo=fixture/dispatch&panel=conversation&task=#{task.id}")

    assert has_element?(view, "#task-dispatch", "Despachar para o Claude Code")
    refute Runners.active_for_task?(task.id)

    view |> element("#dispatch-#{task.id}-trigger") |> render_click()

    phrase =
      AgentBoard.Actions.phrase(:dispatch_task, %{
        task: Repo.preload(task, :repository),
        executor: "claude",
        ceiling_usd: 5.0
      })

    assert has_element?(view, "#dispatch-#{task.id}-q", phrase)
    refute Runners.active_for_task?(task.id)

    view |> element("#dispatch-#{task.id}-confirm") |> render_click()
    assert_receive {:launched, _run_dir}, 1_000
    Process.sleep(100)
    _ = render(view)

    assert has_element?(view, "#task-dispatch", "execução em andamento")
    assert Runners.active_for_task?(task.id)
    assert Repo.get!(Task, task.id).state == "running"
  end

  test "a failed execution proposes the other executor, with the reason", %{
    conn: conn,
    task: task
  } do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert!(%AgentBoard.Runners.Execution{
      task_id: task.id,
      repository_id: task.repository_id,
      executor: "claude",
      status: "failed",
      run_dir: "/tmp/dispatch-failed",
      error: "429 quota exhausted",
      started_at: now,
      finished_at: now
    })

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/dispatch&panel=conversation&task=#{task.id}")

    assert has_element?(view, "#task-dispatch", "Mandar para o Codex")
    view |> element("#dispatch-#{task.id}-trigger") |> render_click()

    assert has_element?(view, "#dispatch-#{task.id}-q", "O último executor falhou")

    view |> element("#dispatch-#{task.id}-confirm") |> render_click()
    assert_receive {:launched, _run_dir}, 1_000
    Process.sleep(100)
    _ = render(view)

    assert Repo.get!(Task, task.id).executor == "codex"
  end

  test "the settings panel saves the dispatch numbers and rejects an invalid reserve", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/?repo=fixture/dispatch&panel=settings")

    view
    |> form("#dispatch-settings-form-dispatch-settings", %{
      "monthly_usd" => "100",
      "task_usd" => "2.50",
      "codex_timeout_minutes" => "15",
      "reserve_percent" => "25",
      "claude_model" => "claude-test",
      "codex_model" => "codex-test"
    })
    |> render_submit()

    assert Settings.get("dispatch_monthly_usd") == "100.00"
    assert Settings.get("dispatch_task_usd") == "2.50"
    assert Settings.get("dispatch_codex_timeout_minutes") == "15"
    assert Settings.get("dispatch_reserve_percent") == "25"
    assert Settings.get("dispatch_claude_model") == "claude-test"
    assert Settings.get("dispatch_codex_model") == "codex-test"

    view
    |> form("#dispatch-settings-form-dispatch-settings", %{
      "monthly_usd" => "100",
      "task_usd" => "2.50",
      "codex_timeout_minutes" => "15",
      "reserve_percent" => "150",
      "claude_model" => "claude-test",
      "codex_model" => "codex-test"
    })
    |> render_submit()

    assert Settings.get("dispatch_reserve_percent") == "25"
    assert has_element?(view, "#dispatch-settings-form-dispatch-settings [role=alert]")
  end

  test "the owner can stop the active execution from the inspector", %{
    conn: conn,
    task: task
  } do
    {:ok, view, _html} =
      live(conn, "/?repo=fixture/dispatch&panel=conversation&task=#{task.id}")

    view |> element("#dispatch-#{task.id}-trigger") |> render_click()
    view |> element("#dispatch-#{task.id}-confirm") |> render_click()
    assert_receive {:launched, _run_dir}, 1_000
    Process.sleep(100)
    _ = render(view)

    view |> element("#stop-execution-#{task.id}-trigger") |> render_click()
    assert has_element?(view, "#stop-execution-#{task.id}-q", "Parar a execução")
    view |> element("#stop-execution-#{task.id}-confirm") |> render_click()
    Process.sleep(100)
    _ = render(view)

    execution = Repo.one!(AgentBoard.Runners.Execution)
    assert execution.status == "stopped"
    assert Repo.get!(Task, task.id).state == "blocked"
  end

  test "the global pause stops a new dispatch and is visible on the board", %{
    conn: conn,
    task: task
  } do
    :ok = Settings.put("dispatch_paused", "true")

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/dispatch&panel=conversation&task=#{task.id}")

    assert has_element?(view, "#task-dispatch", "despacho pausado")
    refute has_element?(view, "#dispatch-#{task.id}-trigger")
    assert has_element?(view, "#task-dispatch", "Retomar despacho")
  end
end
