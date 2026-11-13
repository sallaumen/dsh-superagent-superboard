defmodule AgentBoardWeb.PreflightTest do
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias AgentBoard.{Board, Preflight, Repo}
  alias AgentBoard.Board.Task
  alias AgentBoard.Runners.Execution

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = System.get_env("SUPERBOARD_PREFLIGHT_DIR")
    System.put_env("SUPERBOARD_PREFLIGHT_DIR", tmp)

    on_exit(fn ->
      if previous,
        do: System.put_env("SUPERBOARD_PREFLIGHT_DIR", previous),
        else: System.delete_env("SUPERBOARD_PREFLIGHT_DIR")
    end)

    :ok
  end

  test "script results reach both views, survive reload, and stop at the first failed command", %{
    conn: conn,
    tmp_dir: tmp
  } do
    # Use a disposable git checkout and stub just the commands the gate runs.
    # The preflight script, its writer, and the board reader are real.
    dir = Path.join(tmp, "work")
    File.mkdir_p!(Path.join(dir, "scripts"))

    for file <- ~w(ci-local.sh ci-progress.py),
        do: File.cp!("scripts/#{file}", "#{dir}/scripts/#{file}")

    File.mkdir_p!(Path.join(dir, "scripts/ui-review"))
    File.cp!("scripts/ui-review/select.py", "#{dir}/scripts/ui-review/select.py")
    {_, 0} = System.cmd("git", ["init", "-q", dir])

    {_, 0} =
      System.cmd("git", [
        "-C",
        dir,
        "-c",
        "user.name=fixture",
        "-c",
        "user.email=a@example.org",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "--allow-empty",
        "-qm",
        "fixture"
      ])

    {_, 0} = System.cmd("git", ["-C", dir, "update-ref", "refs/remotes/origin/main", "HEAD"])

    {:ok, repo} = Board.add_repository("fixture", "local-progress")

    task =
      Repo.insert!(
        Task.changeset(%Task{}, %{
          repository_id: repo.id,
          kind: "issue",
          number: 37,
          title: "Local preflight fixture",
          state: "running",
          executor: "codex"
        })
      )

    execution =
      Repo.insert!(
        Execution.changeset(%Execution{}, %{
          repository_id: repo.id,
          task_id: task.id,
          executor: "codex",
          run_dir: tmp,
          worktree: dir,
          started_at: DateTime.utc_now(),
          status: "running"
        })
      )

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/local-progress")
    refute has_element?(view, "#task-#{task.id} [aria-label='Validação local']")
    run = report(dir, ["start", "backend", ""])
    send(view.pid, :merge_check_tick)
    assert has_element?(view, "#task-#{task.id}", "Validação local: Backend · Rodando")
    view |> element("#task-#{task.id} .ab-run__title") |> render_click()
    assert has_element?(view, "#conversation [aria-current=step]", "Backend")

    # Select from the effective checkout: no UI for a clean or backend-only
    # tree, then an untracked hook, a committed hook, and its pending deletion.
    selector = fn ->
      {reason, 0} = System.cmd("python3", ["scripts/ui-review/select.py"], cd: dir)
      String.trim(reason)
    end

    assert selector.() == "none"
    File.write!(Path.join(dir, "mix.exs"), "# backend only")
    assert selector.() == "none"
    File.mkdir_p!(Path.join(dir, "assets/js"))
    File.write!(Path.join(dir, "assets/js/changed.js"), "")
    assert selector.() == "interaction"
    {_, 0} = System.cmd("git", ["add", "assets/js/changed.js"], cd: dir)

    {_, 0} =
      System.cmd(
        "git",
        [
          "-c",
          "user.name=fixture",
          "-c",
          "user.email=a@example.org",
          "-c",
          "commit.gpgsign=false",
          "commit",
          "-qm",
          "UI change"
        ],
        cd: dir
      )

    assert selector.() == "interaction"
    {_, 0} = System.cmd("git", ["update-ref", "refs/remotes/origin/main", "HEAD"], cd: dir)
    File.rm!(Path.join(dir, "assets/js/changed.js"))
    assert selector.() == "interaction"

    for {cmd, rc} <- [{"mix", 0}, {"pg_isready", 0}, {"npm", 23}] do
      file = Path.join(tmp, cmd)
      File.write!(file, "#!/bin/sh\nexit #{rc}\n")
      File.chmod!(file, 0o755)
    end

    {_, 23} =
      System.cmd("bash", ["scripts/ci-local.sh", "all"],
        cd: dir,
        env: [{"PATH", tmp <> ":" <> System.fetch_env!("PATH")}],
        stderr_to_stdout: true
      )

    # Even a late completion from the superseded run cannot overwrite this failure.
    report(dir, ["passed", "library", run])
    for _ <- 1..2, do: send(view.pid, :merge_check_tick)
    assert has_element?(view, "li", "Não executada")
    assert has_element?(view, "#task-#{task.id}", "Validação local: Frontend · Falhou")
    {:ok, fresh, _} = live(conn, ~p"/?repo=fixture/local-progress")
    fresh |> element("#task-#{task.id} .ab-run__title") |> render_click()
    assert has_element?(fresh, "li", "Passou")
    assert has_element?(fresh, "li", "Falhou")
    assert has_element?(fresh, "li", "Não executada")
    assert Preflight.read(Preflight.source(%{execution | started_at: DateTime.utc_now()})) == nil

    # A named DSH ticket reads the same worktree evidence. A number alone
    # could refer to a task from another repository.
    ticket = %{
      "execution" => %{"directory" => dir},
      "repository" => "fixture/local-progress",
      "started_at" => execution.started_at
    }

    assert %{state: "failed"} = ticket |> Preflight.source() |> Preflight.read()
    refute ticket |> Map.delete("repository") |> Preflight.source()

    # Losing the reporter does not create a pass. A completed retry replaces
    # the failed attempt; a focused command cannot replace an all run.
    retry_run = report(dir, ["start", "backend", ""])
    [receipt] = Path.wildcard(Path.join(tmp, "*.json"))

    stale =
      receipt |> File.read!() |> Jason.decode!() |> Map.put("at", System.os_time(:second) - 61)

    File.write!(receipt, Jason.encode!(stale))
    assert %{state: "unconfirmed"} = ticket |> Preflight.source() |> Preflight.read()
    report(dir, ["passed", "library", retry_run])

    {_, 0} =
      System.cmd("bash", ["scripts/ci-local.sh", "library"],
        cd: dir,
        env: [{"PATH", tmp <> ":" <> System.fetch_env!("PATH")}]
      )

    assert %{
             state: "passed",
             rows: [{"backend", "passed"}, {"frontend", "passed"}, {"library", "passed"}]
           } = ticket |> Preflight.source() |> Preflight.read()

    File.mkdir_p!(Path.join(dir, "assets/js"))
    File.write!(Path.join(dir, "assets/js/changed.js"), "// changed")
    File.write!(Path.join(dir, "scripts/check_assets.sh"), "exit 0")
    File.write!(Path.join(tmp, "npm"), "#!/bin/sh\nexit 0")
    File.write!(Path.join(tmp, "mix"), "#!/bin/sh\n[ \"$1\" != run ] || exit 11")

    {_, 11} =
      System.cmd("bash", ["scripts/ci-local.sh"],
        cd: dir,
        env: [{"PATH", tmp <> ":" <> System.fetch_env!("PATH")}],
        stderr_to_stdout: true
      )

    send(fresh.pid, :merge_check_tick)
    assert has_element?(fresh, "#task-#{task.id}", "Revisão de UI · Falhou")
    assert has_element?(fresh, "#conversation", "O código de interação do navegador mudou.")
    assert has_element?(fresh, "#conversation", "Falha na verificação: Inspetor da tarefa.")

    assert %{
             rows: [
               {"backend", "passed"},
               {"frontend", "passed"},
               {"library", "passed"},
               {"ui_review", "failed"}
             ]
           } = ticket |> Preflight.source() |> Preflight.read()
  end

  defp report(dir, args) do
    {out, 0} =
      System.cmd("python3", ["scripts/ci-progress.py" | args], cd: dir, env: [{"UI_REASON", nil}])

    String.trim(out)
  end
end
