# Run by ci-local.sh after the test database and compiled assets exist.
unless Mix.env() == :test, do: raise("UI review requires MIX_ENV=test")

defmodule BrowserReview do
  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  def run do
    # :http port 0 reserves the actual listener, including concurrent worktrees.
    endpoint = Application.fetch_env!(:agent_board, AgentBoardWeb.Endpoint)

    Application.put_env(
      :agent_board,
      AgentBoardWeb.Endpoint,
      Keyword.merge(endpoint,
        server: true,
        http: [ip: {127, 0, 0, 1}, port: 0],
        url: [host: "localhost"],
        check_origin: ["//127.0.0.1"]
      )
    )

    Application.put_env(:agent_board, :state_db, "/nonexistent-ui-review/tickets.sqlite")
    {:ok, _} = Application.ensure_all_started(:agent_board)
    Logger.configure(level: :warning)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, ownership_timeout: :infinity)
    :ok = Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    checkout = Path.join(System.tmp_dir!(), "board-quality-review-" <> Ecto.UUID.generate())

    try do
      name = "review-" <> Ecto.UUID.generate()
      {:ok, repo} = Board.add_repository("ui-fixture", name)

      # Disposable source for stack detection: no upstream access, all DB writes rolled back.
      File.mkdir_p!(checkout)

      File.write!(
        Path.join(checkout, "package.json"),
        Jason.encode!(%{scripts: %{test: "node --test", lint: "eslint .", build: "vite build"}})
      )

      for args <- [
            ["init", "-q"],
            ["remote", "add", "origin", "https://github.com/ui-fixture/#{name}.git"],
            ["add", "package.json"],
            [
              "-c",
              "user.name=UI Fixture",
              "-c",
              "user.email=fixture@example.org",
              "-c",
              "commit.gpgsign=false",
              "commit",
              "-qm",
              "fixture"
            ]
          ] do
        {_, 0} = System.cmd("git", args, cd: checkout)
      end

      :ok = AgentBoard.Settings.put("dispatch_repo_path:ui-fixture/#{name}", checkout)
      for number <- 1..22, do: Board.add_repository("sample", "project-#{number}")

      task =
        Repo.insert!(
          Task.changeset(%Task{}, %{
            repository_id: repo.id,
            number: 1,
            kind: "issue",
            title: "Review fixture task",
            executor: "codex",
            state: "running"
          })
        )

      # The review runs during this worktree's own preflight. Show that real
      # receipt in the disposable inspector without starting an executor.
      Repo.insert!(
        AgentBoard.Runners.Execution.changeset(%AgentBoard.Runners.Execution{}, %{
          repository_id: repo.id,
          task_id: task.id,
          executor: "codex",
          run_dir: File.cwd!(),
          worktree: File.cwd!(),
          started_at: ~U[2000-01-01 00:00:00Z],
          status: "running"
        })
      )

      blocked = blocked_task(repo, checkout)

      Board.log_event(repo.id, "sync", "ui-fixture/" <> name, %{"errors" => 0})
      {:ok, {{127, 0, 0, 1}, port}} = AgentBoardWeb.Endpoint.server_info(:http)

      {_output, code} =
        System.cmd(
          "node",
          [
            "scripts/ui-review/browser.cjs",
            "http://127.0.0.1:#{port}/?repo=ui-fixture/#{name}",
            to_string(blocked.id)
          ],
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true
        )

      code
    after
      File.rm_rf!(checkout)
      Ecto.Adapters.SQL.Sandbox.checkin(Repo)
    end
  end

  # Keep synthetic evidence inside this fixture, including when the smoke
  # test runs alongside a real preflight. Preserve the running card's receipt.
  defp blocked_task(repo, checkout) do
    receipt_dir = Path.join(checkout, ".receipts")
    File.mkdir_p!(receipt_dir)

    source =
      System.get_env(
        "SUPERBOARD_PREFLIGHT_DIR",
        Path.expand("~/.local/state/superboard/preflight")
      )

    key = receipt_key(File.cwd!())

    for suffix <- [".json", ".stages.json"],
        path = Path.join(source, key <> suffix),
        File.regular?(path),
        do: File.cp!(path, Path.join(receipt_dir, key <> suffix))

    System.put_env("SUPERBOARD_PREFLIGHT_DIR", receipt_dir)
    now = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

    File.write!(
      Path.join(receipt_dir, receipt_key(checkout) <> ".stages.json"),
      Jason.encode!(%{
        head: String.duplicate("a", 40),
        started: now,
        at: now,
        stage: "mix-test",
        state: "failed",
        stages: ~w(mix-format mix-lint mix-test),
        reasons: %{"mix-format" => "required", "mix-lint" => "matched", "mix-test" => "required"}
      })
    )

    task =
      Repo.insert!(
        Task.changeset(%Task{}, %{
          repository_id: repo.id,
          number: 2,
          kind: "issue",
          title: "Documentar o próximo passo após a falha de publicação",
          body: String.duplicate("Histórico da tarefa. ", 90),
          executor: "codex",
          state: "blocked"
        })
      )

    Repo.insert!(
      AgentBoard.Runners.Execution.changeset(%AgentBoard.Runners.Execution{}, %{
        repository_id: repo.id,
        task_id: task.id,
        executor: "codex",
        run_dir: checkout,
        worktree: checkout,
        started_at: ~U[2000-01-01 00:00:00Z],
        status: "done"
      })
    )

    Repo.insert!(
      AgentBoard.Board.Comment.changeset(%AgentBoard.Board.Comment{}, %{
        task_id: task.id,
        github_id: 1,
        kind: "agent",
        author: "agente",
        body: """
        ## Relatório do agente

        ### Bloqueio
        A publicação parou porque mix test falhou. Nenhum PR foi criado e nenhum check foi desabilitado. O teste temporário permanece na branch de trabalho. Preciso da sua decisão antes de continuar a entrega.
        """
      })
    )

    task
  end

  defp receipt_key(dir),
    do: :crypto.hash(:sha256, Path.expand(dir)) |> Base.encode16(case: :lower)
end

code =
  try do
    BrowserReview.run()
  rescue
    error ->
      IO.puts(:stderr, "UI review fixture unavailable: #{Exception.message(error)}")
      2
  end

System.halt(code)
