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

  use Gettext, backend: AgentBoardWeb.Gettext

  require Logger

  alias AgentBoard.{Board, Orchestrator, Repo}
  alias AgentBoard.Board.Repository
  alias AgentBoard.Superagents.Prototype

  @start_timeout_ms 90_000

  @doc "Ask the runner for a new Assignment on the ticket; record it."
  @spec retry(String.t() | nil, keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def retry(ticket_id, opts \\ [])

  def retry(nil, _opts),
    do: {:error, gettext("The board did not find the agent's ticket for this task.")}

  def retry(ticket_id, opts) do
    client =
      Keyword.get_lazy(opts, :client, fn -> Orchestrator.client_for(opts[:repository_id]) end)

    result = Orchestrator.retry(client, ticket_id)
    record(ticket_id, Keyword.get(opts, :repository_id), Keyword.get(opts, :number), result)

    case result do
      {:ok, :retried} ->
        {:ok, gettext("New attempt requested. The agent starts when a worker is free.")}

      {:error, reason} ->
        {:error, retry_reason(reason)}
    end
  end

  defp retry_reason({:refused, "notRetryable"}),
    do:
      gettext(
        "The agent refused: it only retries a ticket whose last word was a failure or a block, with no message from you after it."
      )

  defp retry_reason({:refused, "ticketEnded"}),
    do: gettext("The agent refused: the ticket has already ended.")

  defp retry_reason({:refused, "ticketStopped"}),
    do: gettext("The agent refused: someone stopped the ticket.")

  defp retry_reason({:refused, code}),
    do: gettext("The agent refused (%{code}).", code: code || gettext("no code"))

  defp retry_reason(:unknown_ticket), do: gettext("The agent does not know this ticket.")

  defp retry_reason(:unreachable),
    do: gettext("The agent did not answer. Restart the agent and try again.")

  defp retry_reason(:timeout),
    do:
      gettext("The agent did not answer in time. Check in a moment whether the attempt started.")

  defp retry_reason(:not_configured), do: gettext("The agent's API is turned off on this board.")

  defp retry_reason({:http, status}),
    do: gettext("The agent answered with HTTP error %{status}.", status: status)

  defp record(ticket_id, repository_id, number, result) do
    outcome = if match?({:ok, _}, result), do: "retried", else: "error"
    Logger.info("agent_retry_manual ticket=#{ticket_id} outcome=#{outcome}")

    if repository_id do
      target = if number, do: " on ##{number}", else: ""

      # The event is stored: it is written in English whoever asked.
      subject =
        Gettext.with_locale(AgentBoardWeb.Gettext, "en", fn -> subject(result, target) end)

      Board.log_event(repository_id, "agent_retry_manual", subject, %{
        "ticket_id" => ticket_id,
        "number" => number,
        "outcome" => outcome
      })

      Board.broadcast(repository_id)
    end

    :ok
  end

  defp subject({:ok, _}, target), do: "Retry requested by you#{target}"

  defp subject({:error, reason}, target),
    do: "Retry requested by you#{target} was not accepted: #{retry_reason(reason)}"

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
        {:ok, gettext("The agent is up.")}

      {:ok, {output, status}} ->
        # The same reading DshManager makes: a health check that gave up is a
        # slow boot, not a failed one.
        if String.contains?(output, "Startup health check timed out") do
          {:ok,
           gettext(
             "The agent was started; its health check has not answered yet. Check in a moment."
           )}
        else
          {:error,
           gettext("The agent did not come up (exit %{status}): %{line}",
             status: status,
             line: last_line(output)
           )}
        end

      {:exit, reason} ->
        {:error,
         gettext("The command that restarts the agent failed: %{reason}", reason: inspect(reason))}

      nil ->
        {:error,
         gettext(
           "The agent did not answer in %{seconds} s. It may still be coming up; check in a moment.",
           seconds: div(timeout, 1000)
         )}
    end
  end

  # The same manager the LaunchAgent uses (scripts/agent/keepalive.sh), but
  # without --respect-stop: the owner asked for it.
  defp run_manager do
    manager = Prototype.manager()

    if File.exists?(manager) do
      System.cmd("python3", [manager, "start"], stderr_to_stdout: true)
    else
      {"the manager is not at #{manager}; set DSH_SUPERAGENT_HOME", 127}
    end
  rescue
    exception -> {Exception.message(exception), 1}
  end

  defp last_line(output) do
    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> case do
      nil -> "no output"
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
