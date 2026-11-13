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
    view |> form(form_id, %{"stages" => ["npm-build", "npm-test", "npm-lint"]}) |> render_submit()
    assert {:ok, ["npm-lint", "npm-test", "npm-build"]} = ProjectStages.load(repo)
    assert {:ok, []} = ProjectStages.load(other)
    bookmark = assert_patch(view)
    {:ok, again, _} = live(conn, bookmark)
    render_async(again, 5_000)
    assert has_element?(again, form_id <> " input[value=npm-test][checked]")
    refute has_element?(again, form_id <> " input[value=pytest][checked]")

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

    for {command, state} <- [
          {"npm run lint", "Passou"},
          {"npm test", "Falhou"},
          {"npm run build", "Não executada"}
        ] do
      row = board |> element("#conversation .ab-merge-progress li", command) |> render()
      assert row =~ state
    end
  end
end
