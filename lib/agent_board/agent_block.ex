defmodule AgentBoard.AgentBlock do
  @moduledoc """
  What the board says about a ticket whose worker failed: one line for the
  card, what the system will do, what is left to the owner, the whole error
  and every attempt.

  Built from the normalized ticket and `AgentBoard.AutoRetry.plan/2`, so the
  card in Precisa de você, the row in Agora and the detail say the same
  thing. Pure: the clock, the reader's offset and whether the orchestrator
  answers come in as options.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.{AgentFailure, AutoRetry, Time}

  @type state :: :scheduled | :queued | :exhausted | :needs_person
  @type attempt :: %{n: pos_integer(), at: DateTime.t() | nil, text: String.t()}
  @type t :: %{
          state: state(),
          headline: String.t(),
          line: String.t(),
          system: String.t(),
          action: String.t(),
          error: String.t() | nil,
          retry: String.t() | nil,
          ticket_id: String.t() | nil,
          attempts: [attempt()]
        }

  @doc """
  The block for a ticket, or nil when its latest Assignment did not fail and
  no retry waits for a worker (a question, a `blocked` report, work).

  Options: `:now`, `:tz_offset` (minutes), `:agent` (`:up`, `:down` or
  `:unknown`), `:retries` (the board's `agent_retries` rows, to tell an
  automatic retry from one a person asked for) and the `plan/2` options.
  """
  @spec explain(map() | nil, keyword()) :: t() | nil
  def explain(nil, _opts), do: nil

  def explain(ticket, opts) do
    case AutoRetry.plan(ticket, Keyword.take(opts, [:leftover?, :delays])) do
      nil -> if AutoRetry.queued_retry?(ticket), do: queued(ticket, opts)
      plan -> from_plan(ticket, plan, opts)
    end
  end

  defp from_plan(ticket, plan, opts) do
    headline = AgentFailure.headline(plan.failure)
    {line, system, action, retry} = words(plan, headline, ticket, opts)

    %{
      state: plan.state,
      headline: headline,
      line: "**#{headline}.** " <> line,
      system: system,
      action: action,
      error: plan.failure.summary,
      retry: retry,
      ticket_id: ticket["id"],
      attempts: attempts(ticket, opts)
    }
  end

  defp words(%{state: :scheduled} = plan, _headline, _ticket, opts) do
    count = gettext("(%{attempt} of %{max})", attempt: plan.attempt, max: plan.max)
    attempt = [attempt: plan.attempt, max: plan.max]

    {line, system} =
      case when_due(plan, opts) do
        :agent_down ->
          {gettext("Automatic retry when the agent is back %{attempts}.", attempts: count),
           gettext(
             "The board asks for attempt %{attempt} of %{max} as soon as the orchestrator answers, without you.",
             attempt
           )}

        :soon ->
          {gettext("Automatic retry in a moment %{attempts}.", attempts: count),
           gettext(
             "The board asks for attempt %{attempt} of %{max} within the next minute, without you.",
             attempt
           )}

        {:at, time} ->
          {gettext("Automatic retry at %{time} %{attempts}.", time: time, attempts: count),
           gettext(
             "The board asks for attempt %{attempt} of %{max} at %{time}, without you.",
             [time: time] ++ attempt
           )}
      end

    {line, system, gettext("Nothing to do. To skip the wait, press Try now."), gettext("Try now")}
  end

  defp words(%{state: :exhausted} = plan, _headline, _ticket, _opts) do
    where =
      if plan.failure.cause in [:rate_limit, :provider_unavailable],
        do: gettext("the provider"),
        else: gettext("the network")

    {gettext("The %{max} automatic attempts failed; try again when %{where} is back.",
       max: plan.max,
       where: where
     ), gettext("The board stopped trying on its own after %{max} attempts.", max: plan.max),
     gettext("Check %{where} and press Try again.", where: where), gettext("Try again")}
  end

  defp words(%{state: :needs_person, leftover: true}, _headline, ticket, _opts) do
    dir = get_in(ticket, ["execution", "directory"])

    {gettext(
       "The prepare step left files in the ticket's folder; delete the folder and try again."
     ),
     gettext(
       "The board does not retry on its own: the agent would treat those files as a ready worktree."
     ), gettext("Delete %{dir} and press Try again.", dir: dir), gettext("Try again")}
  end

  defp words(%{state: :needs_person, failure: %{cause: :hung}}, _headline, _ticket, _opts) do
    {gettext("Check the bot's access to GitHub and try again."),
     gettext(
       "The board does not retry on its own: the prepare step waited ten minutes, which usually means a password prompt."
     ), gettext("Run gh-agent auth status; with the right login, press Try again."),
     gettext("Try again")}
  end

  defp words(%{state: :needs_person}, _headline, _ticket, _opts) do
    {gettext(
       "This does not look like a network failure: read the error in the details before trying again."
     ), gettext("The board does not retry on its own: this error does not look temporary."),
     gettext(
       "Read the error below, fix the cause and press Try again, or reply in the conversation."
     ), gettext("Try again")}
  end

  defp when_due(plan, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    cond do
      Keyword.get(opts, :agent) == :down -> :agent_down
      is_nil(plan.due_at) or DateTime.compare(plan.due_at, now) != :gt -> :soon
      true -> {:at, Time.local_time(plan.due_at, Keyword.get(opts, :tz_offset, 0))}
    end
  end

  defp queued(ticket, opts) do
    retries = AutoRetry.streak(ticket)
    max = AutoRetry.max_retries()

    count =
      if retries in 1..max,
        do: " " <> gettext("(%{attempt} of %{max})", attempt: retries, max: max),
        else: ""

    %{
      state: :queued,
      headline: gettext("Retry queued"),
      line: gettext("**Retry queued.** Waiting for a free worker%{attempts}.", attempts: count),
      system: gettext("The agent starts as soon as a worker is free."),
      action: gettext("Nothing to do."),
      error: previous_error(ticket),
      retry: nil,
      ticket_id: ticket["id"],
      attempts: attempts(ticket, opts)
    }
  end

  defp previous_error(ticket) do
    (ticket["assignments"] || [])
    |> Enum.reverse()
    |> Enum.find_value(fn assignment ->
      if assignment["report"] == "failed", do: assignment["summary"]
    end)
  end

  @doc "Every Assignment of the ticket as an attempt: when, and what happened."
  @spec attempts(map(), keyword()) :: [attempt()]
  def attempts(ticket, opts \\ []) do
    offset = Keyword.get(opts, :tz_offset, 0)

    automatic =
      for row <- Keyword.get(opts, :retries, []),
          row.outcome == "retried",
          into: %{},
          do: {row.assignment_id, row.updated_at}

    (ticket["assignments"] || [])
    |> Enum.with_index(1)
    |> Enum.map(fn {assignment, n} ->
      %{
        n: n,
        at: assignment["report_at"] || assignment["started_at"] || assignment["created_at"],
        text: outcome(assignment) <> ending(assignment, automatic, offset)
      }
    end)
  end

  # A failure the board recognizes is named in its words (the whole error is
  # shown once, above the list); any other keeps the runner's text.
  defp outcome(%{"report" => "failed", "summary" => summary}) do
    case AgentFailure.classify(summary) do
      %{transient: true} = failure ->
        gettext("failed: %{reason}", reason: lowercase_first(AgentFailure.headline(failure)))

      _other ->
        gettext("failed: %{reason}", reason: excerpt(summary || gettext("no message")))
    end
  end

  defp outcome(%{"report" => "blocked"}), do: gettext("blocked")
  defp outcome(%{"report" => "waiting"}), do: gettext("waited for an answer")
  defp outcome(%{"report" => "ready"}), do: gettext("delivered")
  defp outcome(%{"report" => "progress"}), do: gettext("working")
  defp outcome(%{"state" => "pending"}), do: gettext("queued")
  defp outcome(%{"state" => "running"}), do: gettext("running")
  defp outcome(_assignment), do: gettext("ended without a report")

  defp ending(%{"ended_reason" => "retried", "id" => id}, automatic, offset) do
    case Map.get(automatic, id) do
      nil -> "; " <> gettext("retry requested")
      at -> "; " <> gettext("automatic retry at %{time}", time: Time.local_time(at, offset))
    end
  end

  defp ending(%{"ended_reason" => "hostRestarted"}, _automatic, _offset),
    do: "; " <> gettext("the agent restarted")

  defp ending(_assignment, _automatic, _offset), do: ""

  defp lowercase_first(<<first::utf8, rest::binary>>),
    do: String.downcase(<<first::utf8>>) <> rest

  defp excerpt(text) do
    text = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > 140, do: String.slice(text, 0, 139) <> "…", else: text
  end
end
