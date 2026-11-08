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
    test_pid = self()

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

    assert has_element?(view, "#dispatch-#{task.id}", "Despacho iniciado")
    assert Runners.active_for_task?(task.id)
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
