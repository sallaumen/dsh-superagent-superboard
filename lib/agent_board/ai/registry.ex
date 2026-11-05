defmodule AgentBoard.AI.Registry do
  @moduledoc """
  Every call the panel is allowed to make, as a literal list.

  Adding one is a code change with a test: a caller cannot invent a prompt.
  `tier` picks the model class (`:fast` for refine/split, `:deep` for the
  hard decision), `output_cap` bounds one answer, and `json_schema` is the
  contract the answer is decoded against.
  """

  @refine_schema %{
    "type" => "object",
    "properties" => %{
      "goal" => %{"type" => "string"},
      "constraints" => %{"type" => "array", "items" => %{"type" => "string"}},
      "non_goals" => %{"type" => "array", "items" => %{"type" => "string"}},
      "risks" => %{"type" => "array", "items" => %{"type" => "string"}},
      "open_questions" => %{"type" => "array", "items" => %{"type" => "string"}},
      "assumptions" => %{"type" => "array", "items" => %{"type" => "string"}},
      "ready" => %{"type" => "boolean"},
      "language" => %{"type" => "string", "enum" => ["pt", "en"]}
    },
    "required" => [
      "goal",
      "constraints",
      "non_goals",
      "risks",
      "open_questions",
      "assumptions",
      "ready",
      "language"
    ]
  }

  @tasks_schema %{
    "type" => "object",
    "properties" => %{
      "tasks" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "title" => %{"type" => "string"},
            "body" => %{"type" => "string"},
            "kind" => %{
              "type" => "string",
              "enum" => ["bug", "feature", "design", "docs", "refactor"]
            },
            "acceptance" => %{"type" => "array", "items" => %{"type" => "string"}},
            "depends_on" => %{"type" => "array", "items" => %{"type" => "integer"}},
            "size" => %{"type" => "string", "enum" => ["S", "M", "L"]}
          },
          "required" => ["title", "body", "kind", "acceptance", "depends_on", "size"]
        }
      }
    },
    "required" => ["tasks"]
  }

  @answer_schema %{
    "type" => "object",
    "properties" => %{"answer" => %{"type" => "string"}},
    "required" => ["answer"]
  }

  @summary_schema %{
    "type" => "object",
    "properties" => %{"summary" => %{"type" => "string"}},
    "required" => ["summary"]
  }

  @calls %{
    summarize_board: %{
      name: :summarize_board,
      tier: :fast,
      output_cap: 512,
      system: """
      You speak the state of a software board out loud, to its owner.
      Reply with JSON only, matching the schema.
      Two short sentences, no lists, no markdown, no numbers you were not given.
      Say what is running, what waits for review and whether anything is blocked.
      """,
      json_schema: @summary_schema
    },
    answer_question: %{
      name: :answer_question,
      tier: :fast,
      output_cap: 1024,
      system: """
      You answer a developer's question about one task of their board.
      Reply with JSON only, matching the schema.
      Be concrete and short. If the data does not support an answer, say so
      in the answer instead of guessing.
      """,
      json_schema: @answer_schema
    },
    refine_request: %{
      name: :refine_request,
      tier: :fast,
      output_cap: 1024,
      system: """
      You turn a rough software request into a precise specification.
      Reply with JSON only, matching the schema.
      Do not invent requirements. Ask in open_questions only what changes what
      would be built; a choice you can make yourself goes in assumptions.
      Set ready to true when the goal, the constraints and the first step are
      clear enough to split into tasks, even if secondary questions remain.
      goal is one sentence: the result the user wants.
      """,
      json_schema: @refine_schema
    },
    propose_tasks: %{
      name: :propose_tasks,
      tier: :fast,
      output_cap: 4096,
      system: """
      You split a refined specification into independent tasks.
      Reply with JSON only, matching the schema.
      Each task must close on its own: title, body, acceptance criteria.
      depends_on uses indices of this list, only when there is a real order.
      A size L task is almost always two tasks.
      Keep every constraint and non_goal; a task that violates one is wrong.
      Keep each body under 400 characters: the whole list must fit one answer.
      """,
      json_schema: @tasks_schema
    }
  }

  @spec fetch(atom()) :: {:ok, map()} | {:error, :unknown_call}
  def fetch(name), do: from_call(Map.get(@calls, name))

  defp from_call(nil), do: {:error, :unknown_call}
  defp from_call(spec), do: {:ok, spec}

  @spec names() :: [atom()]
  def names, do: Map.keys(@calls)
end
