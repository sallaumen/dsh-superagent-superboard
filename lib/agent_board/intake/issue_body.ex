defmodule AgentBoard.Intake.IssueBody do
  @moduledoc """
  The text of an issue born from a split.

  The agent reads one issue and nothing else, so the issue carries what the
  whole request decided: the goal, the limits, what was assumed and what is
  still open. The headings follow the request's language (the `language` of
  the refined specification), never the interface's.
  """

  @labels %{
    "pt" => %{
      acceptance: "Critérios de aceite",
      context: "Contexto do pedido",
      goal: "Objetivo",
      constraints: "Restrições",
      non_goals: "Fora do escopo",
      assumptions: "Suposições",
      open_questions: "Perguntas em aberto",
      depends_on: "Depende de",
      read_first: "Leia essas issues antes de começar e confira o que já foi entregue."
    },
    "en" => %{
      acceptance: "Acceptance criteria",
      context: "Request context",
      goal: "Goal",
      constraints: "Constraints",
      non_goals: "Out of scope",
      assumptions: "Assumptions",
      open_questions: "Open questions",
      depends_on: "Depends on",
      read_first: "Read those issues before starting and check what was already delivered."
    }
  }

  @lists ~w(constraints non_goals assumptions open_questions)a

  @doc "The body of one task, with the decisions of the request it came from."
  @spec render(map(), map()) :: String.t()
  def render(task, spec) do
    labels = labels(spec["language"])

    [
      task.body,
      "## #{labels.acceptance}\n#{bullets(task.acceptance)}",
      context(spec, labels)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  @doc "The body with the issues it depends on at the top, as links GitHub resolves."
  @spec with_dependencies(String.t(), [pos_integer()], String.t() | nil) :: String.t()
  def with_dependencies(body, [], _language), do: body

  def with_dependencies(body, numbers, language) do
    labels = labels(language)
    links = Enum.map_join(numbers, ", ", &"##{&1}")

    "**#{labels.depends_on}:** #{links}\n#{labels.read_first}\n\n#{body}"
  end

  defp context(spec, labels) do
    goal = if spec["goal"] in [nil, ""], do: nil, else: "**#{labels.goal}:** #{spec["goal"]}"

    case Enum.reject([goal | Enum.map(@lists, &section(spec, &1, labels))], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(["## #{labels.context}" | parts], "\n\n")
    end
  end

  defp section(spec, name, labels) do
    case spec[Atom.to_string(name)] do
      [_ | _] = items -> "### #{Map.fetch!(labels, name)}\n#{bullets(items)}"
      _none -> nil
    end
  end

  defp bullets(items), do: Enum.map_join(items, "\n", &"- #{&1}")

  defp labels(language), do: Map.get(@labels, language, @labels["pt"])
end
