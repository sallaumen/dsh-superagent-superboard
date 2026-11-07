defmodule AgentBoard.Routing do
  @moduledoc """
  Where a new task should go: a suggestion, never a dispatch
  (docs/research/alfred.md, 3.5, mode "sugerir").

  `suggest/2` is pure. It applies the signals in the plan's order and says
  why in sentences the owner reads:

  1. **Hard restriction**: the DeepSeek runner watches one repository; it is
     out in any other one the board read. When the orchestrator does not
     answer, the repository is unknown and the runner stays the board's
     default, as before the router: an issue with the mention waits for it
     to come back, and in a repository it does not watch does nothing.
  2. **The owner's explicit choice** decides when there is one.
  3. **Availability**: a paused runner is out (the owner paused it). Claude
     Code and Codex have no reader yet, so their availability is unknown,
     which never rules them out and never counts as available.
  4. **Budget, kind and size, history**: there is no usage ledger yet, so
     none of them orders anything; the caller keeps them in the snapshot.
  5. **Order**: the DeepSeek runner first (the only executor the board
     dispatches itself), then the fixed order of `Executors.all/0`.

  The expected cost is the executor's own currency once the usage ledger
  exists; until then it is `:unknown`, shown as "desconhecido", never zero.

  Signals are keyed by executor (`"dsh"`, `"claude"`, `"codex"`), each a map
  with `:state` (`:ready`, `:paused`, `:unknown` or `{:unavailable, why}`),
  `:cost` when known, and for the runner `:repository` and `:load`.
  """

  alias AgentBoard.Executors

  @type availability :: :ready | :paused | :unknown | {:unavailable, String.t()}
  @type task :: %{
          required(:repository) => String.t(),
          optional(:work_type) => String.t() | nil,
          optional(:size) => String.t() | nil,
          optional(:requested) => String.t() | nil
        }
  @type signals :: %{optional(String.t()) => map()}
  @type suggestion :: %{
          executor: String.t() | nil,
          reasons: [String.t()],
          alternatives: [%{executor: String.t(), reasons: [String.t()]}],
          ruled_out: [%{executor: String.t(), reason: String.t()}],
          cost: :unknown | term(),
          mode: String.t()
        }

  @doc "The suggested executor for a task, with the reasons, the alternatives and the expected cost."
  @spec suggest(task(), signals()) :: suggestion()
  def suggest(task, signals) do
    {candidates, ruled_out} = rule_out(task, signals)
    requested = requested(task)

    {executor, lead} =
      cond do
        requested in candidates ->
          {requested, ["Você pediu o #{Executors.name(requested)}."]}

        requested ->
          reason = Enum.find_value(ruled_out, &(&1.executor == requested && &1.reason))
          {List.first(candidates), ["Você pediu o #{Executors.name(requested)}, mas #{reason}"]}

        true ->
          {List.first(candidates), []}
      end

    others_out = for out <- ruled_out, out.executor != requested, do: sentence(out.reason)

    %{
      executor: executor,
      reasons: lead ++ others_out ++ why(executor, candidates, signals),
      alternatives:
        for(
          other <- candidates,
          other != executor,
          do: %{executor: other, reasons: note(other, signals)}
        ),
      ruled_out: ruled_out,
      cost: cost(executor, signals),
      mode: "suggest"
    }
  end

  defp requested(task) do
    executor = Map.get(task, :requested)
    if Executors.valid?(executor), do: executor
  end

  # Rules 1 and 3: who cannot take the task now, in the board's order.
  defp rule_out(task, signals) do
    {kept, out} =
      Enum.reduce(Executors.all(), {[], []}, fn executor, {kept, out} ->
        case out_reason(executor, task, signal(signals, executor)) do
          nil -> {[executor | kept], out}
          reason -> {kept, [%{executor: executor, reason: reason} | out]}
        end
      end)

    {Enum.reverse(kept), Enum.reverse(out)}
  end

  defp out_reason("dsh", task, dsh) do
    watched = dsh[:repository]

    cond do
      is_binary(watched) and
          String.downcase(watched) != String.downcase(to_string(task.repository)) ->
        "o DeepSeek só atende o #{watched}."

      dsh[:state] == :paused ->
        "o DeepSeek está pausado."

      true ->
        nil
    end
  end

  defp out_reason(executor, _task, signal) do
    case signal[:state] do
      {:unavailable, why} -> "o #{Executors.name(executor)} não está disponível (#{why})."
      _ -> nil
    end
  end

  defp silence(%{state: {:unavailable, why}}), do: why
  defp silence(_dsh), do: "o orquestrador não respondeu"

  defp why(nil, _candidates, _signals), do: ["Nenhum executor pode receber a tarefa agora."]

  defp why("dsh", _candidates, signals) do
    dsh = signal(signals, "dsh")

    if is_binary(dsh[:repository]) do
      load =
        case dsh[:load] do
          %{running: running, max_workers: max} -> " Agora: #{running} de #{max} rodando."
          _ -> ""
        end

      ["O DeepSeek atende este repositório e é o único que o board despacha sozinho." <> load]
    else
      [
        "Não deu para ler qual repositório o DeepSeek atende (#{silence(dsh)}): fica o padrão do board, a issue com a menção, que só anda se ele vigiar este repositório."
      ]
    end
  end

  defp why(executor, candidates, signals) do
    order =
      case Enum.drop_while(candidates, &(&1 != executor)) do
        [^executor, next | _] ->
          [
            "Sem histórico de tarefas parecidas, o #{Executors.name(executor)} vem antes do #{Executors.name(next)} na ordem fixa."
          ]

        _ ->
          []
      end

    order ++ note(executor, signals)
  end

  # What the board does not know about an executor it cannot read yet.
  defp note("dsh", _signals), do: []

  defp note(executor, signals) do
    if signal(signals, executor)[:state] == :ready,
      do: [],
      else: ["A disponibilidade do #{Executors.name(executor)} é desconhecida."]
  end

  defp cost(nil, _signals), do: :unknown
  defp cost(executor, signals), do: signal(signals, executor)[:cost] || :unknown

  defp signal(signals, executor), do: Map.get(signals, executor) || %{}

  defp sentence(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
end
