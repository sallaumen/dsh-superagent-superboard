defmodule AgentBoard.AutoRetry do
  @moduledoc """
  Retries a ticket whose worker failed for a passing reason, so a network
  blip (the reboot of 2026-11-07: DNS down, the model's transport failing)
  resolves without the owner clicking anything.

  The one write the board makes in the runner, authorized by the owner on
  2026-11-07 and bounded in `docs/maintainer-contract.md` ("Automatic
  retry"):

    * only the latest Assignment, only when its report is `failed` and
      `AgentBoard.AgentFailure` reads it as transient; a prepare failure that
      left files in the ticket's directory needs a person (the runner would
      take them for a prepared worktree);
    * at most three retries per failure streak (the trailing Assignments that
      failed, counted from the runner's own `endedReason: "retried"`, whoever
      asked), after 1, 5 and 15 minutes;
    * one retry per Assignment id, ever: an `agent_retries` row is claimed
      before the request (unique index), so a board restart or a second
      board on the same database cannot ask twice;
    * only when the orchestrator answers `GET /state` first;
    * every request is an `agent_retry` event in the activity panel and a
      log line.

  `plan/2` is pure and is what the board shows; `tick/1` acts on it. The
  GenServer runs a tick every `:auto_retry_interval` (30 s); the test
  environment stretches it, and `config :agent_board, auto_retry: false`
  switches the writes off (a second board on another database).
  """
  use GenServer

  import Ecto.Query, warn: false
  require Logger

  alias AgentBoard.{Actions, AgentFailure, AgentState, Board, Orchestrator, Repo}
  alias AgentBoard.AutoRetry.{Attempt, Plan}
  alias AgentBoard.Board.Repository

  # An unanswered request may be sent again for the same Assignment, but not
  # on every tick: a runner that accepts connections and never answers would
  # otherwise get a POST every 30 s.
  @reclaim_after 60

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule()

    try do
      tick()
    rescue
      # The sqlite or the database can fail mid-tick; the schedule survives.
      exception -> Logger.warning("auto_retry tick failed: #{Exception.message(exception)}")
    end

    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :tick, interval())
  defp interval, do: Application.get_env(:agent_board, :auto_retry_interval, 30_000)

  @doc "The most retries the board asks for in one failure streak."
  def max_retries, do: Plan.max_retries()

  @doc "The decision for a ticket's latest failure; see `AgentBoard.AutoRetry.Plan.plan/2`."
  def plan(ticket, opts \\ []), do: Plan.plan(ticket, opts)

  @doc "Whether the latest Assignment is a retry still waiting for a worker."
  def queued_retry?(ticket), do: Plan.queued_retry?(ticket)

  @doc "The retries already made in the current failure streak."
  def streak(ticket), do: Plan.streak(ticket)

  @doc """
  One pass: retry every ticket whose plan is due, on the agent of its
  repository. Asks nothing when nothing is due, and retries nothing on an
  agent whose `GET /state` does not answer. Returns
  `[{ticket_id, outcome}]` for the requests it made.

  Options: `:now`, `:tickets` (normalized), `:client`, and the `plan/2`
  options.
  """
  @spec tick(keyword()) :: [{String.t(), String.t()}]
  def tick(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    if Application.get_env(:agent_board, :auto_retry, true) do
      opts
      |> Keyword.get_lazy(:tickets, &AgentState.tickets/0)
      |> due_plans(opts, now)
      |> retry_due(opts, now)
    else
      []
    end
  end

  defp due_plans(tickets, opts, now) do
    for ticket <- tickets,
        plan = plan(ticket, opts),
        match?(%{state: :scheduled}, plan),
        due?(plan, now),
        do: {ticket, plan}
  end

  defp due?(%{due_at: nil}, _now), do: true
  defp due?(%{due_at: due_at}, now), do: DateTime.compare(due_at, now) != :gt

  # Each agent holds its own tickets and answers for itself: one that is down
  # must not stop the retries of another.
  defp retry_due(due, opts, now) do
    due
    |> Enum.group_by(fn {ticket, _plan} -> client_for(ticket, opts) end)
    |> Enum.flat_map(fn {client, due} -> retry_agent(client, due, now) end)
  end

  defp client_for(ticket, opts) do
    Keyword.get_lazy(opts, :client, fn ->
      Orchestrator.client_for(Board.repository_by_slug(ticket["repository"]))
    end)
  end

  defp retry_agent(client, due, now) do
    case Orchestrator.load(client) do
      {:ok, _load} ->
        Enum.flat_map(due, fn {ticket, plan} -> retry_one(client, ticket, plan, now) end)

      {:error, reason} ->
        Logger.info("auto_retry skipped: orchestrator #{inspect(reason)}, #{length(due)} due")
        []
    end
  end

  defp retry_one(client, ticket, plan, now) do
    case claim(plan, now) do
      {:ok, attempt} ->
        # The standing authorization of the maintainer contract: the gate
        # lets `auto_retry` ask for this one red action without a person.
        result =
          Actions.run(
            :auto_retry_ticket,
            %{client: client, ticket_id: plan.ticket_id, attempt: plan.attempt},
            Actions.system("auto_retry")
          )

        {outcome, detail} = outcome(result)

        {:ok, attempt} =
          attempt
          |> Ecto.Changeset.change(outcome: outcome, detail: detail)
          # Forced: the same second as the claim is no change to Ecto, and it
          # would stamp the database clock instead.
          |> Ecto.Changeset.force_change(:updated_at, DateTime.truncate(now, :second))
          |> Repo.update()

        record(ticket, plan, attempt)
        [{plan.ticket_id, outcome}]

      :taken ->
        []
    end
  end

  # The row comes first: a unique Assignment id is the claim. A row left
  # without an answer (unreachable, timeout) can be claimed again once the
  # cool-down passed; any other row means this Assignment was handled.
  defp claim(plan, now) do
    attrs = %{
      ticket_id: plan.ticket_id,
      assignment_id: plan.assignment_id,
      attempt: plan.attempt,
      cause: Atom.to_string(plan.failure.cause),
      stage: Atom.to_string(plan.failure.stage),
      summary: plan.failure.summary,
      failed_at: plan.failed_at && DateTime.truncate(plan.failed_at, :second),
      outcome: "sending"
    }

    # The clock of the tick, not of the database: the cool-down is measured
    # from when the request went out.
    sent_at = DateTime.truncate(now, :second)

    case %Attempt{inserted_at: sent_at, updated_at: sent_at}
         |> Attempt.changeset(attrs)
         |> Repo.insert(on_conflict: :nothing, conflict_target: :assignment_id) do
      {:ok, %Attempt{id: id} = attempt} when not is_nil(id) -> {:ok, attempt}
      {:ok, _conflict} -> reclaim(plan, now)
      {:error, _changeset} -> :taken
    end
  end

  defp reclaim(plan, now) do
    now = DateTime.truncate(now, :second)
    cutoff = DateTime.add(now, -@reclaim_after, :second)

    query =
      from a in Attempt,
        where:
          a.assignment_id == ^plan.assignment_id and a.outcome in ^Attempt.unanswered() and
            a.updated_at <= ^cutoff,
        select: a

    case Repo.update_all(query, set: [outcome: "sending", updated_at: now]) do
      {1, [attempt]} -> {:ok, attempt}
      _none -> :taken
    end
  end

  defp outcome({:ok, :retried}), do: {"retried", nil}
  defp outcome({:error, {:refused, code}}), do: {"refused", code}
  defp outcome({:error, :unknown_ticket}), do: {"unknown_ticket", nil}
  defp outcome({:error, :unreachable}), do: {"unreachable", nil}
  defp outcome({:error, :timeout}), do: {"timeout", nil}
  defp outcome({:error, {:http, status}}), do: {"error", "HTTP #{status}"}
  defp outcome({:error, reason}), do: {"error", inspect(reason)}

  # The event goes to every repository the ticket worked (its channel
  # issues), so it shows in that board's activity; then the board reloads.
  defp record(ticket, plan, attempt) do
    number = List.first(ticket["numbers"] || [])

    Logger.info(
      "auto_retry ticket=#{plan.ticket_id} assignment=#{plan.assignment_id} " <>
        "attempt=#{attempt.attempt} cause=#{attempt.cause} outcome=#{attempt.outcome}"
    )

    kind = if attempt.outcome == "retried", do: "agent_retry", else: "agent_retry_error"

    payload = %{
      "ticket_id" => plan.ticket_id,
      "assignment_id" => plan.assignment_id,
      "number" => number,
      "attempt" => attempt.attempt,
      "max" => plan.max,
      "cause" => attempt.cause,
      "stage" => attempt.stage,
      "outcome" => attempt.outcome,
      "detail" => attempt.detail
    }

    for repository <- repositories(ticket) do
      Board.log_event(repository.id, kind, subject(number, attempt, plan), payload)
      Board.broadcast(repository.id)
    end

    :ok
  end

  defp subject(number, attempt, plan) do
    target = if number, do: " on ##{number}", else: ""
    what = AgentFailure.describe(plan.failure)
    head = "Automatic retry #{attempt.attempt} of #{plan.max}#{target}"

    case attempt.outcome do
      "retried" -> "#{head}: #{lowercase_first(what)}"
      outcome -> "#{head} was not accepted (#{outcome_text(outcome, attempt.detail)})"
    end
  end

  defp outcome_text("refused", code), do: "the agent refused: #{code || "no code"}"
  defp outcome_text("unknown_ticket", _detail), do: "the agent does not know the ticket"
  defp outcome_text("unreachable", _detail), do: "the agent did not answer"
  defp outcome_text("timeout", _detail), do: "no answer in time"
  defp outcome_text(_outcome, detail), do: detail || "error"

  defp lowercase_first(<<first::utf8, rest::binary>>),
    do: String.downcase(<<first::utf8>>) <> rest

  defp lowercase_first(text), do: text

  defp repositories(ticket) do
    urls = ticket["channel_urls"] || []

    Repo.all(Repository)
    |> Enum.filter(fn repository ->
      marker = "github.com/#{repository.owner}/#{repository.name}/"
      Enum.any?(urls, &String.contains?(&1, marker))
    end)
  end

  @doc "The retries the board asked for on a ticket, oldest first."
  @spec attempts(String.t() | nil) :: [Attempt.t()]
  def attempts(nil), do: []

  def attempts(ticket_id) do
    Repo.all(from a in Attempt, where: a.ticket_id == ^ticket_id, order_by: [asc: a.id])
  end
end
