defmodule AgentBoard.Intake.Clarifications do
  @moduledoc "Reviewed question/answer pairs. Only questions in the proposal can enter the prompt."

  alias AgentBoard.Intake

  @spec questions(map()) :: [String.t()]
  def questions(spec) do
    case Enum.find([spec["blocking_questions"], spec["open_questions"]], &match?([_ | _], &1)) do
      nil ->
        [
          if(spec["language"] == "en",
            do: "What needs clarifying?",
            else: "O que precisa ser esclarecido?"
          )
        ]

      questions ->
        Enum.uniq(questions)
    end
  end

  @spec fields([String.t()], map(), map()) :: map()
  def fields(questions, previous, submitted) when is_map(submitted) do
    Map.new(questions, fn question ->
      key = Intake.question_key(question)

      answer =
        case Map.get(submitted, key) do
          value when is_binary(value) -> value
          _ -> Map.get(previous, key, "")
        end

      {key, answer}
    end)
  end

  def fields(_questions, previous, _submitted), do: previous

  @spec pairs([String.t()], map()) :: [{String.t(), String.t()}]
  def pairs(questions, fields) do
    for q <- Enum.uniq(questions),
        answer = String.trim(Map.get(fields, Intake.question_key(q), "")),
        answer != "",
        do: {q, answer}
  end

  @spec sufficient?(map(), map()) :: boolean()
  def sufficient?(spec, fields) do
    questions = questions(spec)
    answered = pairs(questions, fields)

    answered != [] and
      (spec["blocking_questions"] in [nil, []] or length(answered) == length(questions))
  end

  @spec merge(list(), list()) :: list()
  def merge(history, pairs) do
    values = Map.new(history ++ pairs)
    for q <- Enum.uniq(Enum.map(history ++ pairs, &elem(&1, 0))), do: {q, Map.fetch!(values, q)}
  end

  def line({q, answer}), do: q <> " — " <> answer
  def context(text, []), do: text
  def context(text, pairs), do: text <> "\n\n" <> Enum.map_join(pairs, "\n\n", &line/1)

  def apply_to_spec(spec, []), do: spec

  def apply_to_spec(spec, pairs) do
    answered = Map.new(pairs)

    spec
    |> Map.put("decisions", Enum.map(pairs, &line/1))
    |> Map.update("open_questions", [], &Enum.reject(&1, fn q -> Map.has_key?(answered, q) end))
  end
end
