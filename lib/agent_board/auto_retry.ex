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
  alias AgentBoard.AutoRetry.Attempt
  alias AgentBoard.Board.Repository

  @max_retries 3
  @delays [60, 300, 900]
  # An unanswered request may be sent again for the same Assignment, but not
  # on every tick: a runner that accepts connections and never answers would
  # otherwise get a POST every 30 s.
  @reclaim_after 60

  @type plan :: %{
          state: :scheduled | :exhausted | :needs_person,
          failure: AgentFailure.t(),
          leftover: boolean(),
          ticket_id: String.t() | nil,
          assignment_id: String.t() | nil,
          failed_at: DateTime.t() | nil,
          retries: non_neg_integer(),
          attempt: pos_integer(),
          max: pos_integer(),
          due_at: DateTime.t() | nil
        }

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
  def max_retries, do: @max_retries

  @doc """
  What the board does about a ticket's latest failure, or nil when the
  latest Assignment did not fail (or the ticket ended or was stopped).

  `:scheduled` has a `due_at`; `:exhausted` means the streak already had
  `max` retries; `:needs_person` means the failure is not transient or the
  prepare left files behind. Options: `:delays` (seconds per attempt) and
  `:leftover?` (a function of the ticket's directory, for tests).
  """
  @spec plan(map(), keyword()) :: plan() | nil
  def plan(ticket, opts \\ []) do
    assignments = ticket["assignments"] || []
    latest = List.last(assignments)

    cond do
      ticket["ended_outcome"] || ticket["stopped"] || ticket["archived"] -> nil
      not is_map(latest) or latest["report"] != "failed" -> nil
      true -> build_plan(ticket, latest, assignments, opts)
    end
  end

  defp build_plan(ticket, latest, assignments, opts) do
    failure = AgentFailure.classify(latest["summary"])
    retries = streak_retries(assignments)
    leftover = failure.transient and failure.stage == :prepare and leftover?(ticket, opts)
    failed_at = failed_at(latest)
    state = plan_state(failure, leftover, retries)

    %{
      state: state,
      failure: failure,
      leftover: leftover,
      ticket_id: ticket["id"],
      assignment_id: latest["id"],
      failed_at: failed_at,
      retries: retries,
      attempt: min(retries + 1, @max_retries),
      max: @max_retries,
      due_at: if(state == :scheduled, do: due_at(failed_at, retries + 1, opts))
    }
  end

  @doc "Whether the ticket's latest Assignment is a retry still waiting for a worker."
  @spec queued_retry?(map()) :: boolean()
  def queued_retry?(ticket) do
    open? = !(ticket["ended_outcome"] || ticket["stopped"] || ticket["archived"])

    case Enum.take(ticket["assignments"] || [], -2) do
      [%{"ended_reason" => "retried"}, %{"state" => "pending"}] -> open?
      _other -> false
    end
  end

  @doc "The retries already made in the ticket's current failure streak."
  @spec streak(map()) :: non_neg_integer()
  def streak(ticket), do: streak_retries(ticket["assignments"] || [])

  defp failed_at(assignment),
    do: assignment["report_at"] || assignment["started_at"] || assignment["created_at"]

  defp plan_state(%{transient: false}, _leftover, _retries), do: :needs_person
  defp plan_state(_failure, true, _retries), do: :needs_person
  defp plan_state(_failure, _leftover, retries) when retries >= @max_retries, do: :exhausted
  defp plan_state(_failure, _leftover, _retries), do: :scheduled

  # The retries of this streak: walking back from the latest failure, every
  # Assignment the runner ended as `retried`, until one reported something
  # other than a failure (the ticket made progress or asked a question).
  defp streak_retries(assignments) do
    assignments
    |> Enum.reverse()
    |> Enum.drop(1)
    |> Enum.reduce_while(0, fn assignment, count ->
      cond do
        assignment["report"] not in [nil, "failed"] -> {:halt, count}
        assignment["ended_reason"] == "retried" -> {:cont, count + 1}
        true -> {:cont, count}
      end
    end)
  end

  defp due_at(nil, _attempt, _opts), do: nil

  defp due_at(failed_at, attempt, opts) do
    delays = Keyword.get(opts, :delays, @delays)
    DateTime.add(failed_at, Enum.at(delays, attempt - 1, List.last(delays)), :second)
  end

  # The runner removes an empty directory after a failed prepare and keeps
  # one that holds files; a retry would treat those as a prepared worktree.
  defp leftover?(ticket, opts) do
    case get_in(ticket, ["execution", "directory"]) do
      dir when is_binary(dir) and dir != "" ->
        Keyword.get(opts, :leftover?, &holds_files?/1).(dir)

      _ ->
        false
    end
  end

  defp holds_files?(dir) do
    case File.ls(dir) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  @doc """
  One pass: retry every ticket whose plan is due. Asks the orchestrator
  nothing when nothing is due, and retries nothing when `GET /state` does
  not answer. Returns `[{ticket_id, outcome}]` for the requests it made.

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

  defp retry_due([], _opts, _now), do: []

  defp retry_due(due, opts, now) do
    client = Keyword.get_lazy(opts, :client, &Orchestrator.client/0)

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
    target = if number, do: " em ##{number}", else: ""
    what = AgentFailure.describe(plan.failure)
    head = "Nova tentativa automática #{attempt.attempt} de #{plan.max}#{target}"

    case attempt.outcome do
      "retried" -> "#{head}: #{lowercase_first(what)}"
      outcome -> "#{head} não foi aceita (#{outcome_text(outcome, attempt.detail)})"
    end
  end

  defp outcome_text("refused", code), do: "o agente recusou: #{code || "sem código"}"
  defp outcome_text("unknown_ticket", _detail), do: "o agente não conhece o ticket"
  defp outcome_text("unreachable", _detail), do: "o agente não respondeu"
  defp outcome_text("timeout", _detail), do: "sem resposta a tempo"
  defp outcome_text(_outcome, detail), do: detail || "erro"

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
