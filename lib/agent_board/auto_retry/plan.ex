defmodule AgentBoard.AutoRetry.Plan do
  @moduledoc """
  The decision to retry one ticket's latest failure, and nothing else.

  It reads the ticket the runner normalized (`AgentFailure` classifies the
  summary) and, for a prepare failure, the execution directory; it never
  calls the orchestrator, the database or `Actions`. The tick and the claim
  live in `AgentBoard.AutoRetry`; this module is the part the board can
  explain and test without side effects.
  """

  alias AgentBoard.AgentFailure

  @max_retries 3
  @delays [60, 300, 900]

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
end
