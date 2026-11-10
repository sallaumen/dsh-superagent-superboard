defmodule AgentBoard.AIBudgetTest do
  @moduledoc "The daily cap refuses before the network and the refusal is honest."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.AI
  alias AgentBoard.AI.{Budget, Call}
  alias AgentBoard.Repo

  @stub AgentBoard.AIBudgetTest.Stub

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
      Application.delete_env(:agent_board, :ai_daily_tokens)
    end)

    :ok
  end

  defp answer do
    %{
      "model" => "deepseek-flash",
      "choices" => [
        %{
          "message" => %{
            "content" =>
              ~s({"goal":"x","constraints":[],"non_goals":[],"risks":[],"blocking_questions":[],"open_questions":[],"assumptions":[],"ready":true,"language":"pt"})
          }
        }
      ],
      "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20}
    }
  end

  test "the cap refuses the next call before reaching the engine" do
    Application.put_env(:agent_board, :ai_daily_tokens, 30)

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer()) end)

    assert {:ok, _} = AI.call(:refine_request, %{text: "x"})
    assert Budget.tokens_today() == 30

    assert {:error, :budget_exhausted} = AI.call(:refine_request, %{text: "y"})
    assert Repo.aggregate(Call, :count) == 1
  end

  test "a cap that is not a whole number keeps the default, it does not lift the cap" do
    Application.put_env(:agent_board, :ai_daily_tokens, "30")
    assert Budget.cap() == 5_000_000
  end

  test "a clean day has spent nothing" do
    assert Budget.tokens_today() == 0
    assert Budget.check(:fast) == :ok
  end
end
