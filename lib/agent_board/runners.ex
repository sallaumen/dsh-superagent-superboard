defmodule AgentBoard.Runners do
  @moduledoc """
  Dispatch to a local executor: Claude Code (`claude -p`) or Codex
  (`codex exec`).

  The process is **not** a child of the board. `dispatch/3` writes a run
  directory, starts `scripts/runners/run.sh` in a tmux session, and keeps one
  `runner_executions` row per execution. `tick/0` observes the status and
  result files the runner writes; the ledger observes the transcript and the
  sync observes the PR.

  The owner authorized D1/D3 on 2026-11-08 with the owner's `gh` account and
  these defaults: US$ 300/month, US$ 5 per task for Claude Code, 30 minutes
  for Codex, and 50 % of the weekly Codex window reserved. The settings are
  board-wide (`dispatch_*` keys) and the global pause is `dispatch_paused`.
  """
  import Ecto.Query, warn: false
  require Logger

  alias AgentBoard.{Board, Executors, Repo, Settings}
  alias AgentBoard.Board.Task
  alias AgentBoard.Runners.Execution
  alias AgentBoard.Usage.{Costs, Ledger, Report}

  @active ~w(starting running)
  @claude_default_model "claude-opus-5-5"
  @codex_default_model "gpt-6-sol"
  # The Claude Code run is stopped by --max-budget-usd; this is only the
  # watchdog so a hung process does not stay "running" forever.
  @claude_timeout_seconds 7_200
  @claude_default_bin "/Users/tavano/.asdf/installs/nodejs/22.15.1/lib/node_modules/@anthropic-ai/claude-code/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude"
  @codex_default_bin "/opt/homebrew/bin/codex"

  # ---- settings ---------------------------------------------------------------

  @doc "Whether the global dispatch switch is paused."
  def paused?, do: Settings.get("dispatch_paused") == "true"

  def monthly_usd, do: setting_float("dispatch_monthly_usd", 300.0)
  def task_usd, do: setting_float("dispatch_task_usd", 5.0)
  def codex_timeout_minutes, do: setting_int("dispatch_codex_timeout_minutes", 30)
  def reserve_percent, do: setting_int("dispatch_reserve_percent", 50)
  def claude_model, do: Settings.get("dispatch_claude_model") || @claude_default_model
  def codex_model, do: Settings.get("dispatch_codex_model") || @codex_default_model

  def task_ceiling_usd(_executor), do: task_usd()

  @doc "The local checkout a repository runs in; `dispatch_repo_path:<slug>` wins."
  def repo_path(repository) do
    slug = "#{repository.owner}/#{repository.name}"

    Settings.get("dispatch_repo_path:#{slug}") ||
      Application.get_env(:agent_board, :dispatch_repo_root, Path.expand("~/projects"))
      |> Path.join(repository.name)
  end

  @doc "The latest execution of a task, or nil."
  def latest_for_task(task_id) do
    Repo.one(
      from e in Execution,
        where: e.task_id == ^task_id,
        order_by: [desc: e.id],
        limit: 1
    )
  end

  @doc "Every execution of a task, newest first."
  def for_task(task_id) do
    Repo.all(from e in Execution, where: e.task_id == ^task_id, order_by: [desc: e.id])
  end

  @doc """
  The starting/running executions as items for the Hoje view: the task, the
  repository and the executor, so "o que roda e onde" includes Claude Code
  and Codex, not only the harness.
  """
  @spec running_items() :: [map()]
  def running_items do
    Repo.all(
      from e in Execution,
        where: e.status in ^@active,
        order_by: [asc: e.started_at, asc: e.id],
        preload: [:task, :repository]
    )
    |> Enum.filter(&(&1.task && &1.repository))
    |> Enum.map(fn execution ->
      %{
        id: execution.task.id,
        number: execution.task.number,
        title: execution.task.title,
        state: "running",
        url: execution.task.url,
        repository_id: execution.repository_id,
        repo: "#{execution.repository.owner}/#{execution.repository.name}",
        at: to_datetime(execution.started_at || execution.inserted_at),
        executor: execution.executor,
        executor_name: Executors.name(execution.executor),
        runner: true
      }
    end)
  end

  defp to_datetime(%DateTime{} = at), do: at
  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_datetime(_at), do: nil

  @doc "Whether the task already has an execution starting or running."
  def active_for_task?(task_id) do
    Repo.exists?(from e in Execution, where: e.task_id == ^task_id and e.status in ^@active)
  end

  @doc """
  Checks pause, the one-execution rule, the monthly USD cap (Claude Code) and
  the weekly quota reserve (Codex). The answer is `{:ok, plan}` or
  `{:error, reason}`; nothing is started here.
  """
  def check(task, executor, opts \\ []) do
    cond do
      task.state in ["done", "closed", "stopped", "archived"] -> {:error, :task_closed}
      paused?() -> {:error, :paused}
      active_for_task?(task.id) -> {:error, :already_running}
      executor not in ["claude", "codex"] -> {:error, :unknown_executor}
      not File.exists?(binary(executor)) -> {:error, :runner_missing}
      true -> budget(executor, opts)
    end
  end

  defp budget("claude", opts) do
    cap = monthly_usd()
    ceiling = Keyword.get(opts, :ceiling_usd, task_usd())

    case claude_month_usd() do
      {:ok, spent} when spent >= cap ->
        {:error, :monthly_budget}

      {:ok, _spent} ->
        {:ok, %{ceiling_usd: ceiling, timeout_seconds: @claude_timeout_seconds}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp budget("codex", _opts) do
    quota = Costs.codex_weekly(Ledger.limits())
    timeout = codex_timeout_minutes() * 60

    if quota && quota.used_percent + reserve_percent() > 100 do
      {:error, :quota_reserved}
    else
      {:ok, %{ceiling_usd: nil, timeout_seconds: timeout}}
    end
  end

  # Only the Claude Code rows are summed: the board never adds two
  # currencies. A month with an unpriced row is unknown and refuses rather
  # than pretending the budget is empty.
  defp claude_month_usd do
    start = Date.new!(Date.utc_today().year, Date.utc_today().month, 1)

    rows =
      start
      |> Report.daily()
      |> Enum.filter(&(&1.source == "claude_code"))

    cond do
      rows == [] -> {:ok, 0.0}
      Enum.any?(rows, &is_nil(&1.cost)) -> {:error, :budget_unknown}
      true -> {:ok, rows |> Enum.map(& &1.cost.micros) |> Enum.sum() |> Kernel./(1_000_000)}
    end
  end

  @doc "What the UI shows about the current dispatch state."
  def snapshot do
    quota = Costs.codex_weekly(Ledger.limits())

    %{
      paused: paused?(),
      monthly_usd: monthly_usd(),
      spent_usd: elem(claude_month_usd(), 1),
      task_usd: task_usd(),
      codex_timeout_minutes: codex_timeout_minutes(),
      reserve_percent: reserve_percent(),
      quota: quota
    }
  end

  # ---- dispatch ---------------------------------------------------------------

  @doc """
  What to do after a failed execution (docs/research/alfred.md, 3.5):

    * `:retry` — a transient failure before spending; the same executor.
    * `:switch` — availability (quota, login, credit); the other executor.
    * `:none` — a content failure (tests, block, question): the owner decides.

  The board only proposes; nothing starts without a new confirmation.
  """
  @spec fallback(Execution.t() | nil) ::
          %{kind: :retry | :switch | :budget, executor: String.t(), reason: String.t()} | :none
  def fallback(%Execution{status: "failed"} = execution) do
    other = if execution.executor == "claude", do: "codex", else: "claude"
    text = execution.error || ""

    cond do
      text =~ ~r/error_max_budget|max_budget_usd|budget_usd|teto de or[çc]amento/i ->
        %{
          kind: :budget,
          executor: execution.executor,
          reason: "A última execução parou no teto de orçamento (#{short(text)})."
        }

      text =~
          ~r/quota|rate limit|usage limit|401|402|403|429|login|not logged|unauthorized|authentication/i ->
        %{
          kind: :switch,
          executor: other,
          reason: "A última execução parou por cota ou login (#{short(text)})."
        }

      text =~ ~r/timeout|timed out|transport|network|dns|resolve|connection|temporar|5\d\d/i ->
        %{
          kind: :retry,
          executor: execution.executor,
          reason: "A última execução falhou por rede ou tempo (#{short(text)})."
        }

      true ->
        :none
    end
  end

  # No failed execution (nil, running, done) has no proposal; `:none` is the
  # content failure, where the owner decides.
  def fallback(_execution), do: nil

  defp short(text) do
    text |> to_string() |> String.split("\n") |> hd() |> String.slice(0, 160)
  end

  @doc """
  Starts one execution. The caller is the confirmed `:dispatch_task` action;
  this function still re-checks every gate because a runner that is already
  active must not be started twice. `allow_switch: true` is the confirmed
  fallback to the other executor.
  """
  def dispatch(task, executor, opts \\ []) do
    task = Repo.preload(task, :repository)

    with :ok <- executor_allowed(task, executor, opts),
         {:ok, plan} <- check(task, executor, opts),
         {:ok, repository} <- repository(task),
         :ok <- ensure_repo(repository),
         {:ok, execution} <- insert(task, repository, executor, plan) do
      case launch(execution, task, repository, plan, opts) do
        :ok ->
          switch_task(task, executor)
          mark_running(task)
          {:ok, execution}

        {:error, reason} ->
          fail(execution, "não foi possível iniciar o runner: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp executor_allowed(%{executor: executor}, executor, _opts)
       when executor in ["claude", "codex"],
       do: :ok

  defp executor_allowed(_task, executor, opts)
       when executor in ["claude", "codex"] and is_list(opts),
       do: if(Keyword.get(opts, :allow_switch), do: :ok, else: {:error, :executor_mismatch})

  defp executor_allowed(_task, _executor, _opts), do: {:error, :executor_mismatch}

  defp switch_task(%Task{executor: executor}, executor), do: :ok

  defp switch_task(task, executor) do
    case task |> Task.changeset(%{executor: executor}) |> Repo.update() do
      {:ok, _task} -> Board.broadcast(task.repository_id)
      _ -> :ok
    end
  end

  defp repository(%{repository: %{} = repository}), do: {:ok, repository}
  defp repository(_task), do: {:error, :no_repository}

  defp ensure_repo(repository) do
    if File.dir?(repo_path(repository)), do: :ok, else: {:error, :repo_missing}
  end

  defp insert(task, repository, executor, plan) do
    run_id = Ecto.UUID.generate()
    run_dir = Path.join(root(), run_id)
    branch = "agent/task-#{task.number}-#{String.slice(run_id, 0, 8)}"

    attrs = %{
      task_id: task.id,
      repository_id: repository.id,
      executor: executor,
      status: "starting",
      session_id: if(executor == "claude", do: run_id),
      run_dir: run_dir,
      worktree: Path.join(run_dir, "worktree"),
      branch: branch,
      model: if(executor == "claude", do: claude_model(), else: codex_model()),
      ceiling_micros: plan[:ceiling_usd] && round(plan.ceiling_usd * 1_000_000),
      timeout_seconds: plan[:timeout_seconds],
      started_at: DateTime.utc_now()
    }

    :ok = :filelib.ensure_dir(Path.join(run_dir, "prompt.md"))

    case Repo.insert(Execution.changeset(%Execution{}, attrs)) do
      {:ok, execution} -> {:ok, execution}
      {:error, changeset} -> {:error, changeset}
    end
  rescue
    exception -> {:error, exception}
  end

  defp launch(execution, task, repository, plan, opts) do
    run_dir = execution.run_dir
    script = Keyword.get(opts, :script, script_path())
    prompt = prompt(task, repository, execution)

    :ok = :file.write_file(Path.join(run_dir, "prompt.md"), prompt)

    launch_path = Path.join(run_dir, "launch.sh")

    :ok =
      :file.write_file(
        launch_path,
        launch_script(execution, task, repository, plan, script)
      )

    :ok = :file.change_mode(launch_path, 0o755)

    launcher =
      Keyword.get(opts, :launcher) ||
        Application.get_env(:agent_board, :runner_launcher, &launch_tmux/1)

    case launcher.(run_dir) do
      :ok -> :ok
      {:ok, _session} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, exception}
  end

  defp prompt(task, repository, execution) do
    """
    # Tarefa ##{task.number} — #{task.title}

    Repositório: #{repository.owner}/#{repository.name}
    Branch: #{execution.branch}
    Worktree: #{execution.worktree}

    ## Pedido

    #{task.body || task.title}

    ## Como entregar

    - Leia o AGENTS.md do repositório e siga os contratos dele.
    - Trabalhe só neste worktree e nesta branch.
    - Rode `scripts/ci-local.sh all` no head antes de abrir o PR.
    - Abra o PR com `Closes ##{task.number}` no corpo, usando o `gh` já
      autenticado nesta máquina.
    - Depois do gate verde no head, faça o squash-merge do PR e traga o
      número do PR e o resultado.
    - No GitHub, comece cada comentário com "This is by an automated agent,
      not a human." e mantenha um workpad com `## Relatório do agente`,
      `### Plano`, `### Validação`, `### Pergunta` e `### Bloqueio`.
    """
  end

  defp launch_script(execution, task, repository, plan, script) do
    exports = [
      {"RUN_ID", execution.session_id || Path.basename(execution.run_dir)},
      {"EXECUTOR", execution.executor},
      {"REPO_SLUG", "#{repository.owner}/#{repository.name}"},
      {"REPO_DIR", repo_path(repository)},
      {"TASK_NUMBER", to_string(task.number)},
      {"TASK_TITLE", task.title || ""},
      {"TASK_BODY", task.body || ""},
      {"MODEL", execution.model || ""},
      {"BUDGET_USD", to_string(plan[:ceiling_usd] || "")},
      {"TIMEOUT_SECONDS", to_string(plan[:timeout_seconds] || "")},
      {"BRANCH", execution.branch},
      {"WORKTREE", execution.worktree},
      {"RUN_DIR", execution.run_dir},
      {"PROMPT_FILE", Path.join(execution.run_dir, "prompt.md")},
      {"CLAUDE_BIN", claude_bin()},
      {"CODEX_BIN", codex_bin()}
    ]

    body =
      exports
      |> Enum.map_join("\n", fn {key, value} -> "export #{key}=#{shell_escape(value)}" end)

    """
    #!/bin/bash
    set -u
    PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
    export PATH
    #{body}
    exec /bin/bash #{shell_escape(script)}
    """
  end

  defp launch_tmux(run_dir) do
    session = "ab-" <> Path.basename(run_dir)
    launcher = Path.join(run_dir, "launch.sh")

    case System.cmd(
           "/opt/homebrew/bin/tmux",
           [
             "new-session",
             "-d",
             "-s",
             session,
             "/bin/bash #{launcher}"
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {output, _} ->
        # tmux may be absent in a minimal environment; nohup still keeps the
        # process out of the board.
        case System.cmd("/bin/sh", ["-c", "nohup /bin/bash '#{launcher}' >/dev/null 2>&1 &"]) do
          {_, 0} -> :ok
          {out, _} -> {:error, {:launcher, output <> out}}
        end
    end
  rescue
    exception -> {:error, exception}
  end

  # ---- observation ------------------------------------------------------------

  @doc "Reads the status files of active executions and records what changed."
  def tick do
    Repo.all(from e in Execution, where: e.status in ^@active)
    |> Enum.each(&observe/1)
  end

  defp observe(execution) do
    status = read(execution.run_dir, "status")
    session = read(execution.run_dir, "session_id")

    cond do
      status in ["done", "failed"] ->
        finish(execution, status, session)

      status == "running" and (session != execution.session_id or execution.status != "running") ->
        save(execution, %{status: "running", session_id: session || execution.session_id})

      status == nil and stale?(execution) ->
        finish(execution, "failed", session, "o runner não escreveu o estado a tempo")

      true ->
        :ok
    end
  end

  defp finish(execution, status, session, error \\ nil) do
    result = read(execution.run_dir, "result")
    error = error || read(execution.run_dir, "error")
    cost = read_micros(execution.run_dir, "cost_usd")

    case save(execution, %{
           status: status,
           session_id: session || execution.session_id,
           result: result,
           error: error,
           cost_micros: cost,
           finished_at: DateTime.utc_now()
         }) do
      {:ok, execution} ->
        mark_finished(execution)
        {:ok, execution}

      other ->
        other
    end
  end

  # A local execution is an overlay on the lane, like the runner's ticket:
  # starting it puts the task in Agora; a finished one goes to review; a
  # failure goes to the owner as blocked until a new confirmed dispatch.
  defp mark_running(task), do: put_task_state(task.id, "running")

  defp mark_finished(%Execution{status: "done", task_id: id}), do: put_task_state(id, "ready")
  defp mark_finished(%Execution{status: "failed", task_id: id}), do: put_task_state(id, "blocked")
  defp mark_finished(_execution), do: :ok

  defp put_task_state(id, state) do
    case Repo.get(Task, id) do
      %Task{state: current} = task
      when current not in ["done", "closed", "stopped", "archived"] ->
        task
        |> Task.changeset(%{state: state, state_changed_at: DateTime.utc_now()})
        |> Repo.update()

        Board.broadcast(task.repository_id)

      _ ->
        :ok
    end
  end

  defp stale?(execution) do
    timeout = execution.timeout_seconds || codex_timeout_minutes() * 60

    DateTime.diff(DateTime.utc_now(), execution.started_at || execution.inserted_at, :second) >
      timeout + 120
  end

  defp save(execution, attrs) do
    case execution |> Execution.changeset(attrs) |> Repo.update() do
      {:ok, execution} ->
        Board.broadcast(execution.repository_id)
        {:ok, execution}

      {:error, _changeset} ->
        :error
    end
  end

  defp fail(execution, error),
    do: save(execution, %{status: "failed", error: error, finished_at: DateTime.utc_now()})

  defp read_micros(run_dir, file) do
    case read(run_dir, file) do
      nil ->
        nil

      text ->
        case Float.parse(text) do
          {usd, _} when usd >= 0 -> round(usd * 1_000_000)
          _ -> nil
        end
    end
  end

  defp read(run_dir, file) do
    path = Path.join(run_dir, file)

    # The path is the board's own run directory plus a fixed file name.
    case :file.read_file(path) do
      {:ok, text} -> String.trim(text)
      _ -> nil
    end
  end

  # ---- paths and values -------------------------------------------------------

  def root,
    do: Application.get_env(:agent_board, :runner_root, Path.expand("~/.agent_board/runs"))

  def script_path do
    Application.get_env(
      :agent_board,
      :runner_script,
      Path.expand("scripts/runners/run.sh", File.cwd!())
    )
  end

  def claude_bin, do: Application.get_env(:agent_board, :claude_bin, @claude_default_bin)

  def codex_bin, do: Application.get_env(:agent_board, :codex_bin, @codex_default_bin)

  @doc "The CLI path the executor uses."
  def binary("claude"), do: claude_bin()
  def binary("codex"), do: codex_bin()
  def binary(_executor), do: ""

  defp setting_float(key, default) do
    case Float.parse(Settings.get(key) || "") do
      {value, _} when value >= 0 -> value
      _ -> default
    end
  end

  defp setting_int(key, default) do
    case Integer.parse(Settings.get(key) || "") do
      {value, ""} when value >= 0 -> value
      _ -> default
    end
  end

  defp shell_escape(value) do
    "'" <> String.replace(to_string(value), "'", "'\\''") <> "'"
  end
end
