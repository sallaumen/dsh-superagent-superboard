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
          {:ok, %{spec: spec(), tasks: [task()], status: :ready | :needs_clarification}}
          | {:error, term()}
  def run(text) do
    with {:ok, spec} <- refine(text),
         {:ok, tasks} <- propose(spec) do
      {:ok, %{spec: spec, tasks: tasks, status: status(spec, tasks)}}
    end
  end

  # The model is cautious and marks almost everything not ready, so a false
  # flag cannot be a blocker. It refuses only when the split produced nothing
  # AND the model still has questions: then there is genuinely nothing to do.
  defp status(spec, []),
    do: if((spec["open_questions"] || []) != [], do: :needs_clarification, else: :ready)

  defp status(_spec, _tasks), do: :ready

  # The model decides, not a count: it always asks something, so "any question"
  # would refuse every request -- which is the failure it was meant to prevent.

  defp call(name, inputs, normalizer) do
    with {:ok, result} <- AI.call(name, inputs) do
      {:ok, normalize(normalizer, result.json)}
    end
  end

  defp normalize(:refine_request, %{} = spec), do: spec
  defp normalize(:refine_request, _other), do: %{}

  defp normalize(:propose_tasks, %{"tasks" => tasks}) when is_list(tasks) do
    tasks
    |> Enum.reject(&incomplete?/1)
    |> Enum.map(&normalize_task/1)
  end

  defp normalize(:propose_tasks, _other), do: []

  # A task without a title, a body or an acceptance cannot close on its own:
  # it is dropped, not silently created half-written.
  defp incomplete?(task) do
    task["title"] in [nil, ""] or task["body"] in [nil, ""] or task["acceptance"] in [nil, []]
  end

  defp normalize_task(task) do
    %{
      title: task["title"],
      body: task["body"],
      kind: task["kind"] || "feature",
      acceptance: task["acceptance"] || [],
      depends_on: task["depends_on"] || [],
      size: task["size"] || "M"
    }
  end
end
