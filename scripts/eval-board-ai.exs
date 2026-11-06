Code.require_file("board_ai_eval.exs", __DIR__)

defmodule AgentBoard.BoardAIEval.Runner do
  @moduledoc false

  import Ecto.Query

  alias AgentBoard.AI.{Budget, Call, Providers}
  alias AgentBoard.BoardAIEval
  alias AgentBoard.Board.{Comment, Repository, Task}
  alias AgentBoard.Repo
  alias AgentBoardWeb.VoiceAnswer

  def run([]) do
    report = %{
      mode: "plan_only",
      limits: BoardAIEval.limits(),
      cases:
        BoardAIEval.cases(DateTime.utc_now(), "preview")
        |> Enum.map(&BoardAIEval.case_for_report/1),
      note:
        "No model was called. Automatic checks flag responses; factual approval needs a human review."
    }

    IO.puts(Jason.encode!(report, pretty: true))
  end

  def run(["--live", output_path]) do
    if Path.type(output_path) != :absolute or File.exists?(output_path) or
         not File.dir?(Path.dirname(output_path)) or
         String.starts_with?(output_path, File.cwd!() <> "/") do
      raise "choose a new absolute output path outside the repository"
    end

    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    provider = preflight!()
    limits = BoardAIEval.limits()
    run_id = System.fetch_env!("MIX_TEST_PARTITION")
    cases = BoardAIEval.cases(DateTime.utc_now(), run_id)
    Application.put_env(:agent_board, :ai_provider, provider)
    Application.put_env(:agent_board, :ai_rehearsal, false)
    Application.put_env(:agent_board, :ai_daily_tokens, limits.max_recorded_tokens)

    write_line(output_path, %{
      type: "run",
      mode: "live_model",
      provider: provider,
      run_id: run_id,
      started_at: DateTime.utc_now(),
      limits: limits,
      note: "Cost is the board's recorded estimate, not a provider billing guarantee."
    })

    final =
      Enum.reduce_while(
        cases,
        %{cases_evaluated: 0, attempts: 0, recorded_cost_micros: 0, recorded_tokens: 0},
        fn test_case, totals ->
          if stop?(totals, limits) do
            {:halt, totals}
          else
            before_id = Repo.aggregate(Call, :max, :id) || 0
            response = VoiceAnswer.answer(test_case.snapshot, test_case.question)

            rows =
              Repo.all(from c in Call, where: c.id > ^before_id, order_by: [asc: c.id])

            case_report = %{
              type: "case",
              id: test_case.id,
              question: test_case.question,
              snapshot: test_case.snapshot,
              expected_facts: test_case.expected_facts,
              review_questions: test_case.review_questions,
              assessment: BoardAIEval.assess(test_case, response),
              recorded_calls: Enum.map(rows, &call_report/1),
              ledger_check: ledger_check(response, rows)
            }

            write_line(output_path, case_report)

            totals = %{
              cases_evaluated: totals.cases_evaluated + 1,
              attempts: totals.attempts + length(rows),
              recorded_cost_micros:
                totals.recorded_cost_micros + Enum.sum(Enum.map(rows, &(&1.cost_micros || 0))),
              recorded_tokens:
                totals.recorded_tokens +
                  Enum.sum(Enum.map(rows, &((&1.input_tokens || 0) + (&1.output_tokens || 0))))
            }

            {:cont, totals}
          end
        end
      )

    write_line(
      output_path,
      Map.merge(
        %{type: "summary", finished_at: DateTime.utc_now(), planned_cases: length(cases)},
        final
      )
    )

    IO.puts("Saved structured evaluation to #{output_path}")
  end

  def run(_args) do
    raise ArgumentError,
          "usage: mix run scripts/eval-board-ai.exs [--live /absolute/path/report.jsonl]"
  end

  defp preflight! do
    unless Mix.env() == :test do
      raise "live evaluation requires MIX_ENV=test"
    end

    partition = System.get_env("MIX_TEST_PARTITION", "")

    unless String.starts_with?(partition, "board_ai_eval_") do
      raise "use a dedicated MIX_TEST_PARTITION beginning with board_ai_eval_"
    end

    provider =
      case System.get_env("AI_PROVIDER") do
        "deepseek" -> :deepseek
        "gemini" -> :gemini
        "openai" -> :openai
        _ -> raise "pin AI_PROVIDER to deepseek, gemini or openai"
      end

    unless Providers.configured?(provider) do
      raise "the selected provider has no exported API key"
    end

    unless Repo.aggregate(Call, :count) == 0 && Budget.tokens_today() == 0 &&
             Repo.aggregate(Repository, :count) == 0 && Repo.aggregate(Task, :count) == 0 &&
             Repo.aggregate(Comment, :count) == 0 do
      raise "the dedicated evaluation database must be empty"
    end

    provider
  end

  defp stop?(totals, limits) do
    totals.attempts >= limits.max_cases or
      totals.recorded_cost_micros >= limits.max_recorded_cost_micros or
      totals.recorded_tokens >= limits.max_recorded_tokens
  end

  defp call_report(call) do
    Map.take(call, [
      :id,
      :name,
      :engine,
      :model,
      :status,
      :input_tokens,
      :output_tokens,
      :cost_micros,
      :parse_state,
      :error
    ])
  end

  defp ledger_check({:ok, %{engine: :cache}}, []), do: "cached_answer"
  defp ledger_check({:ok, _response}, [_row]), do: "one_row_for_answer"
  defp ledger_check({:ok, _response}, _rows), do: "review_missing_or_multiple_rows"
  defp ledger_check({:error, _reason}, rows), do: "error_with_#{length(rows)}_rows"

  defp write_line(path, record), do: File.write!(path, Jason.encode!(record) <> "\n", [:append])
end

AgentBoard.BoardAIEval.Runner.run(System.argv())
