defmodule AgentBoard.Routing.Signals do
  @moduledoc """
  What the router reads before it suggests, and the snapshot a decision
  keeps.

  Today only the DeepSeek runner can be read for availability
  (`Orchestrator.dispatch_state/1`: the repository it watches, the pause, the
  load). Claude Code and Codex have no availability reader: their state is
  `:unknown`, which never counts as available. The expected cost comes from
  the usage ledger (`AgentBoard.Usage.Report.expected_costs/0`) in each
  executor's own currency; an executor without history keeps `:unknown`,
  never zero.
  """

  alias AgentBoard.Orchestrator
  alias AgentBoard.Runners
  alias AgentBoard.Usage.Report

  @doc "The signals for `AgentBoard.Routing.suggest/2`."
  @spec read((-> {:ok, map()} | {:error, term()}), (-> map())) :: AgentBoard.Routing.signals()
  def read(dispatch_state \\ &Orchestrator.dispatch_state/0, expected \\ &Report.expected_costs/0) do
    dsh =
      case dispatch_state.() do
        {:ok, %{repository: repository, paused: paused, load: load}} ->
          %{
            repository: repository,
            state: if(paused, do: :paused, else: :ready),
            load: load
          }
          |> put_repositories(repository)

        {:error, reason} ->
          %{
            repository: nil,
            state: {:unavailable, reason(reason)}
          }
          |> put_repositories(nil)
      end

    costs = expected.()

    %{
      "dsh" => with_cost(dsh, costs, "dsh"),
      "claude" => with_cost(%{state: :unknown}, costs, "claude"),
      "codex" => with_cost(%{state: :unknown}, costs, "codex")
    }
  end

  defp put_repositories(signal, primary) do
    configured = configured_repositories()

    if configured == [] do
      signal
    else
      configured =
        if primary && primary not in configured, do: [primary | configured], else: configured

      repositories = configured |> Enum.map(&String.downcase/1) |> Enum.uniq()
      Map.put(signal, :repositories, repositories)
    end
  end

  # The routing read is pure enough to run in tests without the board's
  # database; a settings read failure falls back to the orchestrator's
  # repository instead of taking the suggestion down.
  defp configured_repositories do
    Runners.dsh_repositories()
  rescue
    _exception -> []
  end

  # A cost is stored only when the ledger has one: the snapshot stays as
  # small as before for an executor with no history.
  defp with_cost(signal, costs, executor) do
    case Map.get(costs, executor, :unknown) do
      %{} = cost -> Map.put(signal, :cost, cost)
      _ -> signal
    end
  end

  defp reason(:not_configured), do: "a API do orquestrador está desligada"
  defp reason(:unreachable), do: "o orquestrador não respondeu"
  defp reason(:malformed), do: "o orquestrador respondeu num formato inesperado"
  defp reason({:http, status}), do: "o orquestrador respondeu HTTP #{status}"
  defp reason(_other), do: "o orquestrador não respondeu"
end
