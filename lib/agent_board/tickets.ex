defmodule AgentBoard.Tickets do
  @moduledoc """
  What a runner ticket says about the task: the live state overlay and the
  rules that read a waiting report, an own PR, a question or a retry.

  The sync and the ticket poller both read tickets; this module is the one
  owner of the state rule. It takes the workpad and the "asked?" answer as
  values or lazy functions, so it does not read the board or the database
  itself; the only external read is the retry plan's prepare-directory check.
  """

  alias AgentBoard.{AutoRetry.Plan, Workpad}

  @doc """
  The state a ticket imposes on the task, or nil to keep the issue baseline.

  A ticket whose PR merged is done, whatever its last report said: the
  runner keeps the `ready` or `waiting` report it ended on, and the merge
  is the newer fact. Nothing else about an ended ticket imposes a state.

  A `waiting` report means the executor needs input, not that it asked a
  question. When the newest agent comment is a workpad (`workpad`, the map
  from `AgentBoard.Workpad.parse/1` or a function the caller can leave
  lazy) its fields decide: a filled Pergunta is a question, a filled
  Bloqueio is a block. Otherwise it is a question only when the report or
  the newest agent comment (`asked?`, a boolean or a function) actually
  asks one; a waiting ticket that opened a PR is a review; anything else is
  a block whose reason is the report itself.
  """
  def state(ticket, opts \\ []) do
    cond do
      stopped?(ticket) -> nil
      ticket["ended_outcome"] == "merged" -> "done"
      ticket["report"] == "waiting" -> waiting_state(ticket, opts)
      retrying?(ticket) -> "retrying"
      blocked_ticket?(ticket) -> "blocked"
      ticket["report"] == "ready" -> "ready"
      running_ticket?(ticket) -> "running"
      true -> nil
    end
  end

  @pr_mention ~r/(?:\bPR\b|pull request|\/pull\/)\s*#?\s*\d+/i
  @review_word ~r/\b(review|revis(ão|ao|ar|ado|ada))\b/iu

  defp waiting_state(ticket, opts) do
    case workpad(opts) do
      %{question: question} when is_binary(question) -> "question"
      %{blockage: blockage} when is_binary(blockage) -> "blocked"
      _no_field -> waiting_state_by_text(ticket, opts)
    end
  end

  defp waiting_state_by_text(ticket, opts) do
    summary = ticket["report_summary"] || ""

    cond do
      Workpad.question?(summary) or asked?(opts) -> "question"
      (ticket["own_threads"] || []) != [] or pr_for_review?(summary) -> "ready"
      true -> "blocked"
    end
  end

  defp pr_for_review?(summary), do: summary =~ @pr_mention and summary =~ @review_word

  defp asked?(opts) do
    case Keyword.get(opts, :asked?, false) do
      fun when is_function(fun, 0) -> fun.() == true
      value -> value == true
    end
  end

  defp workpad(opts) do
    case Keyword.get(opts, :workpad) do
      fun when is_function(fun, 0) -> fun.()
      value -> value
    end
  end

  defp stopped?(ticket), do: ticket["stopped"] || ticket["archived"]

  # A failure the board retries by itself, or a retry waiting for a worker:
  # nobody has to act, so the task leaves Precisa de você for Agora
  # (`AgentBoard.AutoRetry`, `AgentBoard.AgentBlock`).
  defp retrying?(ticket) do
    case Plan.plan(ticket) do
      %{state: :scheduled} -> true
      nil -> Plan.queued_retry?(ticket)
      _plan -> false
    end
  end

  defp blocked_ticket?(ticket),
    do: ticket["report"] in ["blocked", "failed"] or ticket["assignment"] == "blocked"

  defp running_ticket?(ticket),
    do: ticket["assignment"] == "running" and is_nil(ticket["idle_at"])
end
