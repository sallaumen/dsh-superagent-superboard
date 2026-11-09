defmodule AgentBoard.Intake do
  @moduledoc """
  A free-text request becomes a refined specification and, from it, tasks.

  The AI is asked twice, both on the fast tier: refine (never inventing a
  requirement -- what is missing becomes an open question) and split (each
  task closes on its own). The result is reviewed before anything is created,
  so the panel can show the pair and the human decide.
  """

  alias AgentBoard.AI

  @type spec :: map()
  @type task :: map()

  @doc "Refines a rough request into a specification."
  @spec refine(String.t()) :: {:ok, spec()} | {:error, term()}
  def refine(text), do: call(:refine_request, %{text: text}, :refine_request)

  @doc "Splits a specification into tasks."
  @spec propose(spec()) :: {:ok, [task()]} | {:error, term()}
  def propose(spec), do: call(:propose_tasks, %{spec: spec}, :propose_tasks)

  @doc """
  The whole intake: refine, then split -- unless the spec still has open
  questions.

  A pipeline that always answers with tasks is worse than one that asks: it
  turns an unclear request into confident, wrong work. When the model could
  not pin the request down, the result is the questions and no tasks.
  """
  @spec run(String.t()) ::
          {:ok,
           %{spec: spec(), tasks: [task()], status: :ready | :needs_clarification | :no_tasks}}
          | {:error, term()}
  def run(text) do
    with {:ok, spec} <- refine(text) do
      maybe_propose(spec)
    end
  end

  defp maybe_propose(%{"blocking_questions" => [_ | _]} = spec), do: needs_clarification(spec)

  defp maybe_propose(%{"ready" => true} = spec) do
    with {:ok, tasks} <- propose(spec) do
      status = if tasks == [], do: :no_tasks, else: :ready
      {:ok, %{spec: spec, tasks: tasks, status: status}}
    end
  end

  defp maybe_propose(spec), do: needs_clarification(spec)

  defp needs_clarification(spec),
    do: {:ok, %{spec: spec, tasks: [], status: :needs_clarification}}

  @doc """
  The tasks with the owner's edits from the review form, keyed by position.
  `source_title` stays: it is what makes the request the same one on a retry.
  """
  @spec edit_tasks([task()], map()) :: [task()]
  def edit_tasks(tasks, edits) do
    tasks
    |> Enum.with_index()
    |> Enum.map(fn {task, index} -> edit_task(task, edits[Integer.to_string(index)]) end)
  end

  defp edit_task(task, %{"title" => title, "body" => body, "acceptance" => acceptance}) do
    %{task | title: title, body: body, acceptance: acceptance_lines(acceptance)}
  end

  defp edit_task(task, _no_edit), do: task

  defp acceptance_lines(text) do
    text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  @doc "Whether a task can still close on its own after the owner's edits."
  @spec complete?(map()) :: boolean()
  def complete?(%{title: title, body: body, acceptance: acceptance}) do
    String.trim(title) != "" and String.trim(body) != "" and acceptance != []
  end

  @doc """
  What the task at `index` depends on among the `selected` positions. A blocker
  the owner left out hands over its own dependencies, so the order survives.
  """
  @spec dependencies_within([task()], non_neg_integer(), MapSet.t(non_neg_integer())) ::
          [non_neg_integer()]
  def dependencies_within(tasks, index, selected) do
    tasks |> Enum.at(index) |> Map.fetch!(:depends_on) |> through_selected(tasks, selected)
  end

  defp through_selected(depends_on, tasks, selected) do
    depends_on
    |> Enum.flat_map(fn dependency ->
      if MapSet.member?(selected, dependency),
        do: [dependency],
        else:
          tasks
          |> Enum.at(dependency)
          |> Map.fetch!(:depends_on)
          |> through_selected(tasks, selected)
    end)
    |> Enum.uniq()
  end

  defp call(name, inputs, normalizer) do
    with {:ok, result} <- AI.call(name, inputs) do
      {:ok, normalize(normalizer, result.json)}
    end
  end

  defp normalize(:refine_request, %{} = spec), do: spec
  defp normalize(:refine_request, _other), do: %{}

  defp normalize(:propose_tasks, %{"tasks" => tasks}) when is_list(tasks) do
    kept = tasks |> Enum.with_index() |> Enum.reject(fn {task, _at} -> incomplete?(task) end)
    positions = kept |> Enum.with_index() |> Map.new(fn {{_task, at}, new} -> {at, new} end)

    drafts =
      Enum.map(kept, fn {task, at} -> normalize_task(task, dependencies(task, at, positions)) end)

    without_cycles(drafts)
  end

  defp normalize(:propose_tasks, _other), do: []

  # A task without a title, a body or an acceptance cannot close on its own:
  # it is dropped, not silently created half-written.
  defp incomplete?(task) do
    task["title"] in [nil, ""] or task["body"] in [nil, ""] or task["acceptance"] in [nil, []]
  end

  # The kind and the size are the model's classification. The registry's
  # schema already refused an answer outside `Task.work_types/0` and
  # `Task.sizes/0`, so they are taken as given, never defaulted.
  defp normalize_task(task, depends_on) do
    %{
      title: task["title"],
      source_title: task["title"],
      body: task["body"],
      kind: task["kind"],
      acceptance: task["acceptance"] || [],
      depends_on: depends_on,
      size: task["size"]
    }
  end

  # An edge that would let a task reach itself is dropped, in list order, so
  # the review and the creation always see a graph with an order.
  defp without_cycles(tasks) do
    edges =
      tasks
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {task, index}, kept ->
        Map.put(kept, index, Enum.reject(task.depends_on, &closes_cycle?(&1, index, kept, tasks)))
      end)

    tasks
    |> Enum.with_index()
    |> Enum.map(fn {task, index} -> %{task | depends_on: edges[index]} end)
  end

  defp closes_cycle?(dependency, index, kept, tasks) do
    dependency == index or
      Enum.any?(Map.get(kept, dependency, []), &closes_cycle?(&1, index, kept, tasks))
  end

  # `depends_on` indexes the list the model wrote, so a dropped task moves
  # the positions after it. A task that is not in the list any more, or that
  # names itself, is no dependency.
  defp dependencies(task, at, positions) do
    (task["depends_on"] || [])
    |> Enum.reject(&(&1 == at))
    |> Enum.flat_map(fn index -> positions |> Map.take([index]) |> Map.values() end)
    |> Enum.uniq()
  end
end
