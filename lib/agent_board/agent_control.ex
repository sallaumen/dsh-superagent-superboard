defmodule AgentBoard.AgentControl do
  @moduledoc """
  The two things the owner can ask of the agent from the board, each after
  a confirmation in the interface:

    * `retry/2` - "Tentar de novo": the runner's `POST tickets/<id>/retry`,
      the same write `AgentBoard.AutoRetry` makes, asked by a person. It is
      recorded as an `agent_retry_manual` event.
    * `start_agent/1` - "Religar o agente": the prototype's own manager,
      `python3 scripts/dsh-superagent start`, which is idempotent (it starts
      no second orchestrator) and clears a stop made on purpose, because the
      owner asked for it. The command runs on this machine, never from the
      browser, and the board waits for it at most `:agent_start_timeout_ms`.

  Both answer `{:ok, text}` or `{:error, text}`: the sentence the interface
  shows, never `inspect/1`.
  """

  require Logger

  alias AgentBoard.{Board, Orchestrator, Repo}
  alias AgentBoard.Board.Repository

  @start_timeout_ms 90_000

  @doc "Ask the runner for a new Assignment on the ticket; record it."
  @spec retry(String.t() | nil, keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def retry(ticket_id, opts \\ [])

  def retry(nil, _opts), do: {:error, "O board não achou o ticket do agente desta tarefa."}

  def retry(ticket_id, opts) do
    client = Keyword.get_lazy(opts, :client, &Orchestrator.client/0)
    result = Orchestrator.retry(client, ticket_id)
    record(ticket_id, Keyword.get(opts, :repository_id), Keyword.get(opts, :number), result)

    case result do
      {:ok, :retried} ->
        {:ok, "Nova tentativa pedida. O agente começa quando houver um worker livre."}

      {:error, reason} ->
        {:error, retry_reason(reason)}
    end
  end

  defp retry_reason({:refused, "notRetryable"}),
    do:
      "O agente recusou: só tenta de novo um ticket cuja última palavra foi uma falha ou um bloqueio, sem mensagem sua depois."

  defp retry_reason({:refused, "ticketEnded"}), do: "O agente recusou: o ticket já terminou."
  defp retry_reason({:refused, "ticketStopped"}), do: "O agente recusou: alguém parou o ticket."
  defp retry_reason({:refused, code}), do: "O agente recusou (#{code || "sem código"})."
  defp retry_reason(:unknown_ticket), do: "O agente não conhece este ticket."
  defp retry_reason(:unreachable), do: "O agente não respondeu. Religue o agente e tente de novo."

  defp retry_reason(:timeout),
    do: "O agente não respondeu a tempo. Confira em instantes se a tentativa começou."

  defp retry_reason(:not_configured), do: "A API do agente está desligada neste board."
  defp retry_reason({:http, status}), do: "O agente respondeu com erro HTTP #{status}."

  defp record(ticket_id, repository_id, number, result) do
    outcome = if match?({:ok, _}, result), do: "retried", else: "error"
    Logger.info("agent_retry_manual ticket=#{ticket_id} outcome=#{outcome}")

    if repository_id do
      target = if number, do: " em ##{number}", else: ""

      subject =
        case result do
          {:ok, _} ->
            "Nova tentativa pedida por você#{target}"

          {:error, reason} ->
            "Nova tentativa pedida por você#{target} não foi aceita: #{retry_reason(reason)}"
        end

      Board.log_event(repository_id, "agent_retry_manual", subject, %{
        "ticket_id" => ticket_id,
        "number" => number,
        "outcome" => outcome
      })

      Board.broadcast(repository_id)
    end

    :ok
  end

  @doc """
  Start the orchestrator with the prototype's manager and say how it went.
  The runner is replaceable (`:agent_starter`, a function returning
  `{output, exit_status}`) so the tests never start a process.
  """
  @spec start_agent(keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def start_agent(opts \\ []) do
    starter =
      Keyword.get(opts, :starter) ||
        Application.get_env(:agent_board, :agent_starter, &run_manager/0)

    timeout = Application.get_env(:agent_board, :agent_start_timeout_ms, @start_timeout_ms)
    task = Task.async(starter)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_output, 0}} ->
        {:ok, "O agente está de pé."}

      {:ok, {output, status}} ->
        {:error, "O agente não subiu (saída #{status}): #{last_line(output)}"}

      {:exit, reason} ->
        {:error, "O comando que religa o agente falhou: #{inspect(reason)}"}

      nil ->
        {:error,
         "O agente não respondeu em #{div(timeout, 1000)} s. Ele pode estar subindo; confira em instantes."}
    end
  end

  # The same manager the LaunchAgent uses (scripts/agent/keepalive.sh), but
  # without --respect-stop: the owner asked for it.
  defp run_manager do
    home =
      System.get_env("DSH_SUPERAGENT_HOME") ||
        Path.expand("~/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype")

    manager = Path.join(home, "scripts/dsh-superagent")

    if File.exists?(manager) do
      System.cmd("python3", [manager, "start"], stderr_to_stdout: true)
    else
      {"o gerenciador não está em #{manager}; defina DSH_SUPERAGENT_HOME", 127}
    end
  rescue
    exception -> {Exception.message(exception), 1}
  end

  defp last_line(output) do
    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> case do
      nil -> "sem saída"
      line -> String.slice(line, 0, 200)
    end
  end

  @doc """
  Reload every board. The caller sends it after showing the result: the
  "Agente fora do ar" item leaves on that reload, with the button in it.
  """
  def refresh_boards do
    for repository <- Repo.all(Repository), do: Board.broadcast(repository.id)
    :ok
  end
end
