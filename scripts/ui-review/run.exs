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

    try do
      name = "review-" <> Ecto.UUID.generate()
      {:ok, repo} = Board.add_repository("ui-fixture", name)

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

      Board.log_event(repo.id, "sync", "ui-fixture/" <> name, %{"errors" => 0})
      {:ok, {{127, 0, 0, 1}, port}} = AgentBoardWeb.Endpoint.server_info(:http)

      {_output, code} =
        System.cmd(
          "node",
          ["scripts/ui-review/browser.cjs", "http://127.0.0.1:#{port}/?repo=ui-fixture/#{name}"],
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true
        )

      code
    after
      Ecto.Adapters.SQL.Sandbox.checkin(Repo)
    end
  end
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
