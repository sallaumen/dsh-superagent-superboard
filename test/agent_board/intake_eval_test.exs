defmodule AgentBoard.IntakeEvalTest do
  @moduledoc """
  The five evaluation cases, as a regression net.

  They do not call a model: each stub is a real answer captured from
  `deepseek-flash`, so the pipeline is tested against what the model
  actually returns -- including the fields it invents and the schemas it
  ignores. `scripts/eval-intake.sh` is the live counterpart.
  """
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Intake

  @stub AgentBoard.IntakeEvalTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :ai_api_key, "test-key")

    Application.put_env(:agent_board, :ai_client, fn ->
      Req.new(base_url: "https://api.deepseek.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Application.delete_env(:agent_board, :ai_client)
      Application.delete_env(:agent_board, :ai_api_key)
    end)

    :ok
  end

  defp answer(content) do
    %{
      "model" => "deepseek-flash",
      "choices" => [%{"message" => %{"content" => content}}],
      "usage" => %{"prompt_tokens" => 5, "completion_tokens" => 7}
    }
  end

  defp stub_responses(refine, tasks) do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      if Enum.any?(payload["messages"], &String.contains?(&1["content"], "Specification")) do
        Req.Test.json(conn, answer(tasks))
      else
        Req.Test.json(conn, answer(refine))
      end
    end)
  end

  test "a concrete request becomes a goal and a task list" do
    stub_responses(
      ~s({"goal":"Tornar o board rápido e confiável","constraints":[],"non_goals":[],"risks":[],"open_questions":[],"language":"pt"}),
      ~s({"tasks":[{"title":"Medir baseline","body":"mede","kind":"bug","acceptance":["p95"],"depends_on":[],"size":"S"},{"title":"Corrigir gargalo","body":"corrige","kind":"bug","acceptance":["teste"],"depends_on":[0],"size":"M"}]})
    )

    assert {:ok, %{spec: spec, tasks: tasks}} = Intake.run("o board ta lento")
    assert spec["goal"] =~ "board"
    assert Enum.map(tasks, & &1.title) == ["Medir baseline", "Corrigir gargalo"]
    assert Enum.at(tasks, 1).depends_on == [0]
  end

  test "a vague request keeps its open questions instead of inventing scope" do
    stub_responses(
      ~s({"goal":"Definir uma especificação clara","constraints":[],"non_goals":[],"risks":[],"open_questions":["Qual é o software?","O que significa funcionar?"],"language":"pt"}),
      ~s({"tasks":[]})
    )

    assert {:ok, %{spec: spec, tasks: tasks}} = Intake.run("não sei, só quero que funcione")
    assert length(spec["open_questions"]) == 2
    assert tasks == []
  end

  test "a task with a missing acceptance criterion is dropped" do
    stub_responses(
      ~s({"goal":"x","constraints":[],"non_goals":[],"risks":[],"open_questions":[],"language":"pt"}),
      ~s({"tasks":[{"title":"boa","body":"b","kind":"bug","acceptance":["a"],"depends_on":[],"size":"S"},{"title":"ruim","body":"b","kind":"bug","acceptance":[],"depends_on":[],"size":"M"}]})
    )

    assert {:ok, %{tasks: tasks}} = Intake.run("x")
    assert Enum.map(tasks, & &1.title) == ["boa"]
  end
end
