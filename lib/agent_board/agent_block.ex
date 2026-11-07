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
    headline = AgentFailure.describe(plan.failure)
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
    count = "(#{plan.attempt} de #{plan.max})"

    {line, system} =
      case when_due(plan, opts) do
        :agent_down ->
          {"Nova tentativa automática quando o agente voltar #{count}.",
           "O board pede a tentativa #{plan.attempt} de #{plan.max} assim que o orquestrador responder, sem você."}

        :soon ->
          {"Nova tentativa automática em instantes #{count}.",
           "O board pede a tentativa #{plan.attempt} de #{plan.max} no próximo minuto, sem você."}

        {:at, time} ->
          {"Nova tentativa automática às #{time} #{count}.",
           "O board pede a tentativa #{plan.attempt} de #{plan.max} às #{time}, sem você."}
      end

    {line, system, "Nada a fazer. Para não esperar, toque em Tentar agora.", "Tentar agora"}
  end

  defp words(%{state: :exhausted} = plan, _headline, _ticket, _opts) do
    where =
      if plan.failure.cause in [:rate_limit, :provider_unavailable],
        do: "o provedor",
        else: "a rede"

    {"As #{plan.max} tentativas automáticas falharam; tente de novo quando #{where} voltar.",
     "O board parou de tentar sozinho depois de #{plan.max} tentativas.",
     "Confira #{where} e toque em Tentar de novo.", "Tentar de novo"}
  end

  defp words(%{state: :needs_person, leftover: true}, _headline, ticket, _opts) do
    dir = get_in(ticket, ["execution", "directory"])

    {"O preparo deixou arquivos na pasta do ticket; apague a pasta e tente de novo.",
     "O board não tenta sozinho: o agente trataria esses arquivos como um worktree pronto.",
     "Apague #{dir} e toque em Tentar de novo.", "Tentar de novo"}
  end

  defp words(%{state: :needs_person, failure: %{cause: :hung}}, _headline, _ticket, _opts) do
    {"Confira o acesso do bot ao GitHub e tente de novo.",
     "O board não tenta sozinho: o preparo esperou dez minutos, o que costuma ser um pedido de senha.",
     "Rode gh-agent auth status; com o login certo, toque em Tentar de novo.", "Tentar de novo"}
  end

  defp words(%{state: :needs_person}, _headline, _ticket, _opts) do
    {"Não parece falha de rede: leia o erro no detalhe antes de tentar de novo.",
     "O board não tenta sozinho: este erro não parece passageiro.",
     "Leia o erro abaixo, resolva a causa e toque em Tentar de novo, ou responda na conversa.",
     "Tentar de novo"}
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
    count = if retries in 1..max, do: " (#{retries} de #{max})", else: ""

    %{
      state: :queued,
      headline: "Nova tentativa na fila",
      line: "**Nova tentativa na fila.** Esperando um worker livre#{count}.",
      system: "O agente começa assim que um worker ficar livre.",
      action: "Nada a fazer.",
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
        "falhou: " <> lowercase_first(AgentFailure.describe(failure))

      _other ->
        "falhou: " <> excerpt(summary || "sem mensagem")
    end
  end

  defp outcome(%{"report" => "blocked"}), do: "bloqueado"
  defp outcome(%{"report" => "waiting"}), do: "esperou uma resposta"
  defp outcome(%{"report" => "ready"}), do: "entregou"
  defp outcome(%{"report" => "progress"}), do: "trabalhando"
  defp outcome(%{"state" => "pending"}), do: "na fila"
  defp outcome(%{"state" => "running"}), do: "rodando"
  defp outcome(_assignment), do: "encerrada sem relatório"

  defp ending(%{"ended_reason" => "retried", "id" => id}, automatic, offset) do
    case Map.get(automatic, id) do
      nil -> "; nova tentativa pedida"
      at -> "; nova tentativa automática às #{Time.local_time(at, offset)}"
    end
  end

  defp ending(%{"ended_reason" => "hostRestarted"}, _automatic, _offset),
    do: "; o agente reiniciou"

  defp ending(_assignment, _automatic, _offset), do: ""

  defp lowercase_first(<<first::utf8, rest::binary>>),
    do: String.downcase(<<first::utf8>>) <> rest

  defp excerpt(text) do
    text = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > 140, do: String.slice(text, 0, 139) <> "…", else: text
  end
end
