defmodule AgentBoard.Freshness do
  @moduledoc """
  How fresh the board is, from the sources that actually answered.

  The board never says "live" from the socket alone. GitHub answers through the
  last sync, the runner answers through its ticket database, and the local
  queue answers through the read that rendered this page. A failed GitHub
  attempt freezes the board even when the last good sync is recent: the data
  is saved, but it is no longer being confirmed.
  """

  @github_ttl 6 * 60
  @stale_ttl 15 * 60
  @agent_running_ttl 2 * 60

  @type state :: :live | :delayed | :reconnecting | :offline | :unknown

  @doc "The expected GitHub cadence, with one minute of grace over the 5-minute cron."
  def github_ttl, do: @github_ttl

  @doc "After this age a successful sync is no longer trusted as current."
  def stale_ttl, do: @stale_ttl

  @doc """
  The board's freshness snapshot.

  `last_attempt` is the newest sync event (success or error), `last_success`
  the newest successful one, and `agent` the result of `AgentBoard.AgentState.snapshot/0`.
  """
  @spec snapshot(map()) :: map()
  def snapshot(opts) do
    opts = Map.new(opts)
    now = Map.get(opts, :now, DateTime.utc_now())
    connected = Map.get(opts, :connected, true)
    last_attempt = Map.get(opts, :last_attempt)
    last_success = Map.get(opts, :last_success)
    agent = Map.get(opts, :agent, %{ok: false, at: nil, tickets: [], error: :unknown})

    age = age_sec(now, last_success && last_success.inserted_at)
    state = state(connected, last_attempt, last_success, age, agent, now)
    at = last_success && last_success.inserted_at

    %{
      state: state,
      age_sec: age,
      at: at,
      frozen?: state == :offline,
      live?: state == :live,
      title: title(state),
      note: note(state, at),
      sources: sources(now, state, last_attempt, last_success, age, agent)
    }
  end

  defp state(connected, last_attempt, last_success, age, agent, now) do
    cond do
      not connected -> :reconnecting
      is_nil(last_attempt) -> :unknown
      last_attempt.kind == "sync_error" -> :offline
      is_nil(last_success) -> :unknown
      true -> healthy_state(age, agent, now, last_success)
    end
  end

  defp healthy_state(age, agent, now, last_success) do
    cond do
      age > @stale_ttl -> :offline
      age > @github_ttl -> :delayed
      errors(last_success) > 0 -> :delayed
      not agent.ok -> :delayed
      running_without_heartbeat?(now, agent) -> :delayed
      true -> :live
    end
  end

  defp running_without_heartbeat?(now, %{ok: true, at: at, tickets: tickets}) do
    running? = Enum.any?(tickets, &(&1["assignment"] == "running" and is_nil(&1["idle_at"])))
    age = age_sec(now, at)
    running? and is_integer(age) and age > @agent_running_ttl
  end

  defp running_without_heartbeat?(_now, _agent), do: false

  defp title(:live), do: "Tudo em dia"
  defp title(:delayed), do: "Dados atrasados"
  defp title(:reconnecting), do: "Reconectando"
  defp title(:offline), do: "Sem conexão com o GitHub"
  defp title(:unknown), do: "Sem dados ainda"

  defp note(:live, _at),
    do: "GitHub, processo do agente e fila local responderam dentro da cadência."

  defp note(:delayed, _at),
    do: "Uma das fontes passou da cadência; os tempos abaixo estão parados."

  defp note(:reconnecting, _at),
    do: "A conexão com o board caiu. O que está na tela é o último estado conhecido."

  defp note(:offline, nil),
    do:
      "Não houve uma sincronia bem-sucedida; os dados salvos são os últimos que chegaram. Nada abaixo mudou desde então — pode ter mudado lá fora."

  defp note(:offline, at),
    do:
      "O último dado completo é de #{time(at)}. Nada abaixo mudou desde então — pode ter mudado lá fora."

  defp note(:unknown, _at),
    do: "Ainda não houve uma sincronia concluída para este repositório."

  defp sources(now, state, last_attempt, last_success, age, agent) do
    [
      github_source(now, state, last_attempt, last_success, age),
      agent_source(now, agent),
      %{
        label: "Fila local",
        kind: :run,
        word: "OK",
        detail: "consultada agora",
        age_sec: 0
      }
    ]
  end

  defp github_source(_now, state, last_attempt, last_success, age) do
    cond do
      is_nil(last_attempt) ->
        %{
          label: "GitHub (PRs, CI)",
          kind: :unknown,
          word: "Sem dados",
          detail: "aguardando a primeira sincronia",
          age_sec: nil
        }

      last_attempt.kind == "sync_error" ->
        %{
          label: "GitHub (PRs, CI)",
          kind: :blocked,
          word: "Falhou",
          detail: "última tentativa às #{time(last_attempt.inserted_at)}",
          age_sec: age
        }

      state == :delayed and errors(last_success) > 0 ->
        %{
          label: "GitHub (PRs, CI)",
          kind: :stale,
          word: "Com erros",
          detail: "#{errors(last_success)} #{plural(errors(last_success))} no último sync",
          age_sec: age
        }

      state == :delayed ->
        %{
          label: "GitHub (PRs, CI)",
          kind: :stale,
          word: "Atrasado",
          detail: "último dado #{ago(age)}",
          age_sec: age
        }

      true ->
        %{
          label: "GitHub (PRs, CI)",
          kind: :run,
          word: "OK",
          detail: "há #{short_age(age)}",
          age_sec: age
        }
    end
  end

  defp errors(nil), do: 0
  defp errors(%{payload: %{"errors" => n}}) when is_integer(n), do: n
  defp errors(_event), do: 0

  defp plural(1), do: "erro"
  defp plural(_n), do: "erros"

  defp agent_source(_now, %{ok: false}), do: agent_unavailable()

  defp agent_source(now, %{ok: true, at: at, tickets: tickets}) do
    age = age_sec(now, at)
    running? = Enum.any?(tickets, &(&1["assignment"] == "running" and is_nil(&1["idle_at"])))

    cond do
      running? and is_integer(age) and age > @agent_running_ttl ->
        %{
          label: "Processo do agente",
          kind: :stale,
          word: "Sem sinal",
          detail: "há #{short_age(age)}; há tarefa em execução sem batimento",
          age_sec: age
        }

      is_nil(at) ->
        %{
          label: "Processo do agente",
          kind: :run,
          word: "OK",
          detail: "lido agora; nenhum ticket ainda",
          age_sec: 0
        }

      true ->
        %{
          label: "Processo do agente",
          kind: :run,
          word: "OK",
          detail: "lido agora; último ticket #{ago(age)}",
          age_sec: 0
        }
    end
  end

  defp agent_unavailable do
    %{
      label: "Processo do agente",
      kind: :blocked,
      word: "Indisponível",
      detail: "o banco do executor não respondeu",
      age_sec: nil
    }
  end

  defp age_sec(_now, nil), do: nil

  defp age_sec(now, at) when is_struct(at, DateTime) do
    max(DateTime.diff(now, at, :second), 0)
  end

  defp age_sec(_now, _at), do: nil

  defp ago(nil), do: "desconhecido"
  defp ago(sec) when sec < 60, do: "há #{sec} s"
  defp ago(sec) when sec < 3600, do: "há #{div(sec, 60)} min"
  defp ago(sec) when sec < 86_400, do: "há #{div(sec, 3600)} h"
  defp ago(sec), do: "há #{div(sec, 86_400)} d"

  defp short_age(nil), do: "indeterminado"
  defp short_age(sec) when sec < 60, do: "#{sec} s"
  defp short_age(sec) when sec < 3600, do: "#{div(sec, 60)} min"
  defp short_age(sec), do: "#{div(sec, 3600)} h"

  defp time(nil), do: "desconhecido"

  defp time(%DateTime{} = at),
    do: at |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)

  defp time(_other), do: "desconhecido"
end
