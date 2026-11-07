defmodule AgentBoard.IntakeTest do
  @moduledoc "Refine then split: the pair the human reviews before tasks are created."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Intake

  @stub AgentBoard.IntakeTest.Stub

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

  @refined ~s({"goal":"o board responde rapido","constraints":["sem quebrar o sync"],"non_goals":[],"risks":[],"open_questions":[],"assumptions":[],"ready":true,"language":"pt"})

  test "refine returns the specification" do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer(@refined)) end)

    assert {:ok, spec} = Intake.refine("o board ta lento")
    assert spec["goal"] == "o board responde rapido"
    assert spec["constraints"] == ["sem quebrar o sync"]
  end

  test "propose drops a task that cannot close on its own" do
    tasks = """
    {"tasks":[
      {"title":"medir","body":"mede o tempo","kind":"bug","acceptance":["p95 < 200ms"],"depends_on":[],"size":"S"},
      {"title":"","body":"sem titulo","kind":"bug","acceptance":[],"depends_on":[],"size":"M"}
    ]}
    """

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer(tasks)) end)

    assert {:ok, [task]} = Intake.propose(%{"goal" => "x"})
    assert task.title == "medir"
    assert task.acceptance == ["p95 < 200ms"]
  end

  test "propose keeps the split's kind of work and size" do
    tasks = """
    {"tasks":[
      {"title":"tela","body":"refaz a tela","kind":"ui","acceptance":["a tela abre"],"depends_on":[],"size":"S"},
      {"title":"medir","body":"mede","kind":"research","acceptance":["p95"],"depends_on":[],"size":"L"}
    ]}
    """

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer(tasks)) end)

    assert {:ok, [ui, research]} = Intake.propose(%{"goal" => "x"})
    assert {ui.kind, ui.size} == {"ui", "S"}
    assert {research.kind, research.size} == {"research", "L"}
  end

  test "a kind outside the board's list is a malformed split, not a guess" do
    tasks = """
    {"tasks":[
      {"title":"tela","body":"refaz","kind":"feature","acceptance":["abre"],"depends_on":[],"size":"S"}
    ]}
    """

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer(tasks)) end)

    assert {:error, :malformed_output} = Intake.propose(%{"goal" => "x"})
  end

  test "the split's schema offers exactly the kinds and sizes a task stores" do
    {:ok, spec} = AgentBoard.AI.Registry.fetch(:propose_tasks)
    item = spec.json_schema["properties"]["tasks"]["items"]["properties"]

    assert item["kind"]["enum"] == AgentBoard.Board.Task.work_types()
    assert item["size"]["enum"] == AgentBoard.Board.Task.sizes()
    assert AgentBoard.Board.Task.work_types() == ~w(ui backend docs bug research infra)
  end

  test "run chains refine and split" do
    tasks = """
    {"tasks":[
      {"title":"medir","body":"mede","kind":"bug","acceptance":["p95"],"depends_on":[],"size":"S"},
      {"title":"corrigir","body":"corrige","kind":"bug","acceptance":["teste"],"depends_on":[0],"size":"M"}
    ]}
    """

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      if Enum.any?(payload["messages"], &String.contains?(&1["content"], "Specification")) do
        Req.Test.json(conn, answer(tasks))
      else
        Req.Test.json(conn, answer(@refined))
      end
    end)

    assert {:ok, %{spec: spec, tasks: tasks}} = Intake.run("o board ta lento")
    assert spec["goal"] == "o board responde rapido"
    assert Enum.map(tasks, & &1.title) == ["medir", "corrigir"]
    assert Enum.at(tasks, 1).depends_on == [0]
  end

  test "run stops after refinement when the request is not ready" do
    refined =
      ~s({"goal":"Melhorar o board","constraints":[],"non_goals":[],"risks":[],"open_questions":["Qual parte?"],"assumptions":[],"ready":false,"language":"pt"})

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer(refined)) end)

    assert {:ok, %{spec: spec, tasks: [], status: :needs_clarification}} =
             Intake.run("melhore o board")

    assert spec["open_questions"] == ["Qual parte?"]
    assert AgentBoard.Repo.aggregate(AgentBoard.AI.Call, :count, :id) == 1
  end

  test "run does not call an empty proposal ready" do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      content =
        if Enum.any?(payload["messages"], &String.contains?(&1["content"], "Specification")) do
          ~s({"tasks":[]})
        else
          @refined
        end

      Req.Test.json(conn, answer(content))
    end)

    assert {:ok, %{tasks: [], status: :no_tasks}} = Intake.run("o board ta lento")
  end
end
