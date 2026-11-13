defmodule AgentBoardWeb.ProjectStagesTest do
  use AgentBoardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias AgentBoard.{Board, ProjectStages, Repo}
  alias AgentBoard.Board.Task
  alias AgentBoard.Runners.Execution

  @moduletag :tmp_dir
  test "choose project stages, reload, and see a failed task's real local results without a PR",
       %{conn: conn, tmp_dir: tmp} do
    env = [{"HOME", tmp}, {"SUPERBOARD_PREFLIGHT_DIR", tmp}]
    Application.put_env(:agent_board, :project_stages_env, env)
    prior = System.get_env("SUPERBOARD_PREFLIGHT_DIR")
    System.put_env("SUPERBOARD_PREFLIGHT_DIR", tmp)

    on_exit(fn ->
      Application.delete_env(:agent_board, :project_stages_env)

      if prior,
        do: System.put_env("SUPERBOARD_PREFLIGHT_DIR", prior),
        else: System.delete_env("SUPERBOARD_PREFLIGHT_DIR")
    end)

    {:ok, repo} = Board.add_repository("fixture", "checks")
    {:ok, other} = Board.add_repository("fixture", "other")
    url = "/?repo=fixture/checks&panel=settings&section=projects"
    {:ok, view, _} = live(conn, url)
    open = "#tracked-#{repo.id} button[phx-click=toggle_project]"
    form_id = "#tracked-#{repo.id}-merge-policy-stage-form"
    view |> element(open) |> render_click()
    render_async(view, 5_000)
    picker = "#tracked-#{repo.id}-merge-policy-language"

    assert has_element?(
             view,
             picker <> " option[value=''][selected]",
             "Tecnologia ainda não detectada"
           )

    refute has_element?(view, form_id)
    view |> element(picker <> "-form") |> render_change(%{"stack" => "JavaScript / TypeScript"})

    view
    |> form(form_id, %{
      "rules" => %{"npm-build" => "always", "npm-test" => "always", "npm-lint" => "always"}
    })
    |> render_submit()

    render_async(view, 5_000)
    assert {:ok, ["npm-lint", "npm-test", "npm-build"]} = ProjectStages.load(repo)
    assert {:ok, []} = ProjectStages.load(other)
    bookmark = assert_patch(view)
    {:ok, again, _} = live(conn, bookmark)
    render_async(again, 5_000)
    again |> element(picker <> "-form") |> render_change(%{"stack" => "JavaScript / TypeScript"})

    assert has_element?(
             again,
             form_id <> " select[name='rules[npm-test]'] option[value=always][selected]"
           )

    dir = Path.join(tmp, "work")
    File.mkdir_p!(dir)
    {_, 0} = System.cmd("git", ["init", "-q"], cd: dir)

    {_, 0} =
      System.cmd(
        "git",
        [
          "-c",
          "user.name=test",
          "-c",
          "user.email=test@example.org",
          "-c",
          "commit.gpgsign=false",
          "commit",
          "--allow-empty",
          "-qm",
          "base"
        ],
        cd: dir
      )

    {_, 0} =
      System.cmd("git", ["remote", "add", "origin", "git@github.com:fixture/checks.git"], cd: dir)

    {:ok, task} =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 1,
        title: "Check task",
        state: "running",
        executor: "codex"
      })
      |> Repo.insert()

    %Execution{}
    |> Execution.changeset(%{
      repository_id: repo.id,
      task_id: task.id,
      executor: "codex",
      run_dir: tmp,
      worktree: dir,
      started_at: DateTime.utc_now(),
      status: "running"
    })
    |> Repo.insert!()

    script = Application.app_dir(:agent_board, "priv/merge_gate/task_stages.py")
    File.write!(Path.join(tmp, "npm"), "#!/bin/sh\n[ \"$1\" != test ] || exit 1\n")
    File.chmod!(Path.join(tmp, "npm"), 0o700)

    {_, 1} =
      System.cmd("python3", [script, "run", "fixture/checks"],
        cd: dir,
        env: [{"PATH", tmp <> ":" <> System.fetch_env!("PATH")} | env],
        stderr_to_stdout: true
      )

    {:ok, board, _} = live(conn, "/?repo=fixture/checks")
    assert has_element?(board, "#task-#{task.id}", "npm test · Falhou")
    board |> element("#task-#{task.id} .ab-run__title") |> render_click()

    assert has_element?(board, "#conversation", "Obrigatória em toda tarefa deste projeto.")
    assert has_element?(board, "#conversation", "Uma etapa anterior interrompeu a execução.")

    for {command, state} <- [
          {"npm run lint", "Passou"},
          {"npm test", "Falhou"},
          {"npm run build", "Não executada"}
        ] do
      row = board |> element("#conversation .ab-merge-progress li", command) |> render()
      assert row =~ state
    end

    # The same task, without a PR or hosted checks: show skipped, then the
    # matching source pattern when a new, untracked file changes the decision.
    {_, 0} = System.cmd("git", ["update-ref", "refs/remotes/origin/main", "HEAD"], cd: dir)
    {:ok, profile} = ProjectStages.profile(repo, dir)

    :ok =
      ProjectStages.save(
        repo,
        %{"npm-test" => "off", "npm-lint" => "changed", "npm-build" => "changed"},
        profile["stored"]
      )

    for {file, expected} <- [
          {"README.md", "Nenhum arquivo alterado corresponde a esta regra."},
          {"new.ts", "Arquivo alterado corresponde a *.ts."}
        ] do
      File.write!(Path.join(dir, file), "")

      {_, 0} =
        System.cmd("python3", [script, "run", "fixture/checks"],
          cd: dir,
          env: [{"PATH", tmp <> ":" <> System.fetch_env!("PATH")} | env],
          stderr_to_stdout: true
        )

      send(board.pid, :merge_check_tick)
      assert has_element?(board, "#conversation", expected)
      assert has_element?(board, "#conversation", "Desativada nas configurações do projeto.")
      assert has_element?(board, "#conversation", "Pulada")
    end
  end
end
