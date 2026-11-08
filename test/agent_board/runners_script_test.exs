defmodule AgentBoard.RunnersScriptTest do
  @moduledoc "O script do runner cria o worktree, roda o executor e grava o estado que o board observa."
  use ExUnit.Case, async: true

  @script Path.expand("../../scripts/runners/run.sh", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "runner-script-#{System.unique_integer([:positive])}")
    remote = Path.join(root, "remote.git")
    repo = Path.join(root, "repo")
    run = Path.join(root, "run")
    File.mkdir_p!(run)

    {_, 0} = System.cmd("git", ["init", "--bare", "--quiet", remote])
    {_, 0} = System.cmd("git", ["init", "--quiet", "-b", "main", repo])

    File.write!(Path.join(repo, "README.md"), "hello\n")
    git(repo, ["add", "README.md"])
    git(repo, ["-c", "user.email=t@example.com", "-c", "user.name=T", "commit", "-qm", "init"])
    git(repo, ["remote", "add", "origin", remote])
    git(repo, ["push", "-q", "origin", "main"])
    File.write!(Path.join(run, "prompt.md"), "Faça o trabalho.\n")

    on_exit(fn -> File.rm_rf!(root) end)

    %{root: root, repo: repo, run: run}
  end

  test "claude: worktree, status, result and session", %{root: root, repo: repo, run: run} do
    fake = fake_claude(root)

    env = %{
      "RUN_DIR" => run,
      "RUN_ID" => "11111111-1111-4111-8111-111111111111",
      "EXECUTOR" => "claude",
      "REPO_SLUG" => "fixture/repo",
      "REPO_DIR" => repo,
      "TASK_NUMBER" => "42",
      "MODEL" => "claude-test",
      "BUDGET_USD" => "5",
      "TIMEOUT_SECONDS" => "20",
      "BRANCH" => "agent/test-claude",
      "WORKTREE" => Path.join(run, "worktree"),
      "PROMPT_FILE" => Path.join(run, "prompt.md"),
      "CLAUDE_BIN" => fake,
      "CODEX_BIN" => fake
    }

    assert {_, 0} = System.cmd("/bin/bash", [@script], env: env, stderr_to_stdout: true)
    assert File.read!(Path.join(run, "status")) == "done\n"
    assert File.read!(Path.join(run, "result")) =~ "fake claude ok"
    assert File.read!(Path.join(run, "session_id")) =~ "11111111"
    assert File.read!(Path.join(run, "cost_usd")) == "0.21\n"
    assert File.dir?(Path.join(run, "worktree"))
  end

  test "claude: a JSON error is written as the execution error", %{
    root: root,
    repo: repo,
    run: run
  } do
    fake = fake_claude_fail(root)

    env = %{
      "RUN_DIR" => run,
      "RUN_ID" => "33333333-3333-4333-8333-333333333333",
      "EXECUTOR" => "claude",
      "REPO_SLUG" => "fixture/repo",
      "REPO_DIR" => repo,
      "TASK_NUMBER" => "44",
      "MODEL" => "claude-test",
      "BUDGET_USD" => "5",
      "TIMEOUT_SECONDS" => "20",
      "BRANCH" => "agent/test-fail",
      "WORKTREE" => Path.join(run, "worktree"),
      "PROMPT_FILE" => Path.join(run, "prompt.md"),
      "CLAUDE_BIN" => fake,
      "CODEX_BIN" => fake
    }

    {_, 0} = System.cmd("/bin/bash", [@script], env: env, stderr_to_stdout: true)
    assert File.read!(Path.join(run, "status")) == "failed\n"
    assert File.read!(Path.join(run, "error")) =~ "Teto de orçamento"
  end

  test "codex: thread id, status and result", %{root: root, repo: repo, run: run} do
    fake = fake_codex(root)
    worktree = Path.join(run, "worktree")

    env = %{
      "RUN_DIR" => run,
      "RUN_ID" => "22222222-2222-4222-8222-222222222222",
      "EXECUTOR" => "codex",
      "REPO_SLUG" => "fixture/repo",
      "REPO_DIR" => repo,
      "TASK_NUMBER" => "43",
      "MODEL" => "gpt-test",
      "BUDGET_USD" => "",
      "TIMEOUT_SECONDS" => "20",
      "BRANCH" => "agent/test-codex",
      "WORKTREE" => worktree,
      "PROMPT_FILE" => Path.join(run, "prompt.md"),
      "CLAUDE_BIN" => fake,
      "CODEX_BIN" => fake
    }

    assert {_, 0} = System.cmd("/bin/bash", [@script], env: env, stderr_to_stdout: true)
    assert File.read!(Path.join(run, "status")) == "done\n"
    assert File.read!(Path.join(run, "session_id")) == "thread-1\n"
    assert File.read!(Path.join(run, "result")) =~ "fake codex ok"
  end

  defp fake_claude(root) do
    path = Path.join(root, "fake-claude")

    File.write!(path, """
    #!/bin/bash
    echo "work" > work.txt
    printf '{"result": "fake claude ok", "session_id": "s", "total_cost_usd": 0.21}\\n'
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp fake_claude_fail(root) do
    path = Path.join(root, "fake-claude-fail")

    File.write!(path, """
    #!/bin/bash
    printf '{"is_error": true, "subtype": "error_max_budget_usd"}\n'
    exit 1
    """)

    File.chmod!(path, 0o755)
    path
  end

  test "codex: a JSON error event is the execution error even on exit 0", %{
    root: root,
    repo: repo,
    run: run
  } do
    fake = fake_codex_fail(root)
    worktree = Path.join(run, "worktree")

    env = %{
      "RUN_DIR" => run,
      "RUN_ID" => "44444444-4444-4444-8444-444444444444",
      "EXECUTOR" => "codex",
      "REPO_SLUG" => "fixture/repo",
      "REPO_DIR" => repo,
      "TASK_NUMBER" => "45",
      "MODEL" => "gpt-test",
      "BUDGET_USD" => "",
      "TIMEOUT_SECONDS" => "20",
      "BRANCH" => "agent/test-codex-fail",
      "WORKTREE" => worktree,
      "PROMPT_FILE" => Path.join(run, "prompt.md"),
      "CLAUDE_BIN" => fake,
      "CODEX_BIN" => fake
    }

    assert {_, 0} = System.cmd("/bin/bash", [@script], env: env, stderr_to_stdout: true)
    assert File.read!(Path.join(run, "status")) == "failed\n"
    assert File.read!(Path.join(run, "session_id")) == "thread-9\n"
    assert File.read!(Path.join(run, "error")) =~ "quota exhausted"
  end

  defp fake_codex_fail(root) do
    path = Path.join(root, "fake-codex-fail")

    File.write!(path, """
    #!/bin/bash
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-o" ]; then out="$2"; shift 2; else shift; fi
    done
    printf '{"type":"thread.started","thread_id":"thread-9"}\n'
    printf '{"type":"error","message":"quota exhausted"}\n'
    exit 0
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp fake_codex(root) do
    path = Path.join(root, "fake-codex")

    File.write!(path, """
    #!/bin/bash
    shift # exec
    # -o last.txt is in the arguments; write the file the script expects.
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-o" ]; then out="$2"; shift 2; else shift; fi
    done
    printf '{"type":"thread.started","thread_id":"thread-1"}\\n'
    printf 'fake codex ok\\n' > "$out"
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp git(dir, args) do
    {_, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
  end
end
