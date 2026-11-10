defmodule AgentBoard.Routing do
  @moduledoc """
  Where a new task should go: a suggestion, never a dispatch
  (docs/research/alfred.md, 3.5, mode "sugerir").

  `suggest/2` and `plan/5` are pure. `suggest/2` applies the signals in the
  plan's order and says why in sentences the owner reads; `plan/5` turns a
  read into the request's executor and the line a `Decision` row keeps. The
  read itself belongs to the door (or to `Actions`, when a request reaches
  it without a line), never to this module:

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

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Board.Task
  alias AgentBoard.Executors
  alias AgentBoard.Repo
  alias AgentBoard.Routing.Decision

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

  @doc """
  Decides a request's executor and builds the router line the board stores.

  Pure: the caller reads the signals at its door and passes them. The
  request's own executor wins (a choice made when the suggestion was
  shown); otherwise the owner's `requested` name; otherwise the suggestion;
  otherwise the board's default. The line keeps the suggestion, a snapshot
  of the signals and the door that decided (`composer`, `voice`, `api`).
  """
  @spec plan(
          %{required(:owner) => String.t(), required(:name) => String.t()},
          map(),
          String.t() | nil,
          String.t(),
          signals()
        ) :: map()
  def plan(%{owner: owner, name: name}, request, requested, decided_by, signals) do
    suggestion =
      suggest(
        %{
          repository: "#{owner}/#{name}",
          work_type: Map.get(request, :work_type),
          size: Map.get(request, :size),
          requested: requested
        },
        signals
      )

    executor =
      cond do
        Executors.valid?(Map.get(request, :executor)) -> request.executor
        Executors.valid?(requested) -> requested
        true -> suggestion.executor || Executors.default()
      end

    request
    |> Map.put(:executor, executor)
    |> Map.put(:routing, %{
      suggestion: suggestion,
      signals: snapshot(signals),
      decided_by: decided_by
    })
  end

  @doc """
  The signals as stored data: strings for every atom and tuple.

  The decision row keeps this snapshot, not the live maps, so reading an old
  decision never depends on today's runner state.
  """
  @spec snapshot(AgentBoard.Routing.signals()) :: map()
  def snapshot(signals) do
    Map.new(signals, fn {executor, signal} -> {executor, Map.new(signal, &stored/1)} end)
  end

  defp stored({key, {:unavailable, why}}), do: {to_string(key), "unavailable: " <> why}

  defp stored({key, value}) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: {to_string(key), to_string(value)}

  defp stored({key, %{} = value}), do: {to_string(key), Map.new(value, &stored/1)}
  defp stored({key, value}) when is_list(value), do: {to_string(key), Enum.join(value, ",")}
  defp stored({key, value}), do: {to_string(key), value}

  @doc """
  Records the router's line for a task the board just created.

  One row per task, owned by this context: the suggestion it showed, the
  executor the owner chose, the snapshot it decided from and the door. The
  ticket already exists, so a failed insert answers the caller, which
  reports it without dropping the task (a retry would open a second issue).
  """
  @spec record(Task.t(), String.t(), map()) ::
          {:ok, Decision.t()} | {:error, Ecto.Changeset.t()}
  def record(%Task{id: task_id}, chosen, routing)
      when is_integer(task_id) and is_binary(chosen) and is_map(routing) do
    suggestion = routing.suggestion

    %Decision{}
    |> Decision.changeset(%{
      task_id: task_id,
      suggested: suggestion.executor,
      chosen: chosen,
      mode: suggestion.mode,
      reasons: suggestion.reasons,
      alternatives: Enum.map(suggestion.alternatives, & &1.executor),
      signals: routing.signals,
      decided_by: routing.decided_by
    })
    |> Repo.insert()
  end

  @doc "The suggested executor for a task, with the reasons, the alternatives and the expected cost."
  @spec suggest(task(), signals()) :: suggestion()
  def suggest(task, signals) do
    {candidates, ruled_out} = rule_out(task, signals)
    requested = requested(task)

    {executor, lead} =
      cond do
        requested in candidates ->
          {requested,
           [gettext("You asked for %{executor}.", executor: Executors.name(requested))]}

        requested ->
          reason = Enum.find_value(ruled_out, &(&1.executor == requested && &1.reason))

          {List.first(candidates),
           [
             gettext("You asked for %{executor}, but %{reason}",
               executor: Executors.name(requested),
               reason: reason
             )
           ]}

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
    watched = dsh[:repositories] || List.wrap(dsh[:repository])
    wanted = String.downcase(to_string(task.repository))

    cond do
      watched != [] and not Enum.any?(watched, &(String.downcase(to_string(&1)) == wanted)) ->
        case watched do
          [one] ->
            gettext("DeepSeek only serves %{repository}.", repository: one)

          many ->
            gettext("DeepSeek only serves %{repositories}.", repositories: Enum.join(many, ", "))
        end

      dsh[:state] == :paused ->
        gettext("DeepSeek is paused.")

      true ->
        nil
    end
  end

  defp out_reason(executor, _task, signal) do
    case signal[:state] do
      {:unavailable, why} ->
        gettext("%{executor} is not available (%{why}).",
          executor: Executors.name(executor),
          why: why
        )

      _ ->
        nil
    end
  end

  defp silence(%{state: {:unavailable, why}}), do: why
  defp silence(_dsh), do: gettext("the orchestrator did not answer")

  defp why(nil, _candidates, _signals), do: [gettext("No executor can take the task now.")]

  defp why("dsh", _candidates, signals) do
    dsh = signal(signals, "dsh")

    if is_binary(dsh[:repository]) do
      load =
        case dsh[:load] do
          %{running: running, max_workers: max} ->
            " " <> gettext("Now: %{running} of %{max} running.", running: running, max: max)

          _ ->
            ""
        end

      [
        gettext(
          "DeepSeek serves this repository and is the only one the board dispatches on its own."
        ) <> load
      ]
    else
      [
        gettext(
          "Could not read which repository DeepSeek serves (%{why}): the board's default stays, the issue with the mention, which only moves if it watches this repository.",
          why: silence(dsh)
        )
      ]
    end
  end

  defp why(executor, candidates, signals) do
    order =
      case Enum.drop_while(candidates, &(&1 != executor)) do
        [^executor, next | _] ->
          [
            gettext("%{executor} comes before %{next} in the fixed order.",
              executor: Executors.name(executor),
              next: Executors.name(next)
            )
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
      else: [
        gettext("The availability of %{executor} is unknown.", executor: Executors.name(executor))
      ]
  end

  defp cost(nil, _signals), do: :unknown
  defp cost(executor, signals), do: signal(signals, executor)[:cost] || :unknown

  defp signal(signals, executor), do: Map.get(signals, executor) || %{}

  defp sentence(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
end
