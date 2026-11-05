defmodule AgentBoardWeb.IntakeUITest do
  @moduledoc "The Split form shows the spec and the tasks before anything is created."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  @stub AgentBoardWeb.IntakeUITest.Stub

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
      "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 2}
    }
  end

  test "the form shows the goal, the open questions and the tasks", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      content =
        if Enum.any?(payload["messages"], &String.contains?(&1["content"], "Specification")) do
          ~s({"tasks":[{"title":"medir o tempo","body":"mede","kind":"bug","acceptance":["p95"],"depends_on":[],"size":"S"}]})
        else
          ~s({"goal":"o board responde rapido","constraints":[],"non_goals":[],"risks":[],"open_questions":["qual volume?"],"language":"pt"})
        end

      Req.Test.json(conn, answer(content))
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    html = view |> element("#intake-form") |> render_submit(%{"text" => "o board ta lento"})

    assert html =~ "o board responde rapido"
    assert html =~ "qual volume?"
    assert html =~ "medir o tempo"
  end
end
