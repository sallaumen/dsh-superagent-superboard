defmodule AgentBoard.AITest do
  @moduledoc "A registered call runs, records its row, and refuses an unregistered name."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.AI
  alias AgentBoard.AI.{Call, Providers}
  alias AgentBoard.Repo

  @stub AgentBoard.AITest.Stub

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
      "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20}
    }
  end

  test "a registered call runs and records its row" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/chat/completions"

      Req.Test.json(
        conn,
        answer(
          ~s({"goal":"x","constraints":[],"non_goals":[],"risks":[],"open_questions":[],"language":"pt"})
        )
      )
    end)

    assert {:ok, result} = AI.call(:refine_request, %{text: "faz o board ficar rapido"})
    assert result.json["goal"] == "x"
    assert result.input_tokens == 10
    assert result.parse_state == :complete

    call = Repo.one(Call)
    assert call.name == "refine_request"
    assert call.status == "ok"
    assert call.output_tokens == 20
    assert call.tier == "fast"
  end

  test "the catalog has deepseek, gemini and openai with a model per tier" do
    assert Providers.ids() == [:deepseek, :gemini, :openai]

    for id <- Providers.ids() do
      assert {:ok, provider} = Providers.fetch(id)
      assert provider.base_url =~ "https://"
      assert provider.key_env =~ "API_KEY"
      assert is_binary(Providers.model(id, :fast))
      assert is_binary(Providers.model(id, :deep))
      refute Providers.model(id, :fast) == Providers.model(id, :deep)
    end

    assert Providers.model(:gemini, :fast) == "gemini-2.5-flash"
  end

  test "a structured call sends a strict tool and decodes its arguments" do
    Req.Test.stub(@stub, fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert [%{"function" => %{"strict" => true, "name" => "respond"}}] = payload["tools"]
      assert payload["tool_choice"]["function"]["name"] == "respond"

      Req.Test.json(conn, %{
        "model" => "deepseek-flash",
        "choices" => [
          %{
            "message" => %{
              "tool_calls" => [
                %{
                  "function" => %{
                    "name" => "respond",
                    "arguments" =>
                      ~s({"goal":"x","constraints":[],"non_goals":[],"risks":[],"open_questions":[],"language":"pt"})
                  }
                }
              ]
            }
          }
        ],
        "usage" => %{"prompt_tokens" => 3, "completion_tokens" => 4}
      })
    end)

    assert {:ok, result} = AI.call(:refine_request, %{text: "x"})
    assert result.json["goal"] == "x"
    assert result.parse_state == :complete
  end

  test "an unregistered call is refused and records nothing" do
    assert {:error, :unknown_call} = AI.call(:nope, %{text: "x"})
    assert Repo.aggregate(Call, :count) == 0
  end

  test "a failed call records the error" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, {:http, 500}} = AI.call(:refine_request, %{text: "x"})

    call = Repo.one(Call)
    assert call.status == "error"
    assert call.error =~ "500"
  end

  test "rehearsal answers without a key or a network" do
    Application.put_env(:agent_board, :ai_api_key, "")
    Application.put_env(:agent_board, :ai_rehearsal, true)
    on_exit(fn -> Application.delete_env(:agent_board, :ai_rehearsal) end)

    assert {:ok, result} = AI.call(:refine_request, %{text: "x"})
    assert result.engine == :rehearsal
    assert result.json["goal"] =~ "board"

    call = Repo.one(Call)
    assert call.engine == "rehearsal"
    assert call.status == "ok"
  end

  test "a missing key is not a network call" do
    Application.put_env(:agent_board, :ai_api_key, "")

    assert {:error, :not_configured} = AI.call(:refine_request, %{text: "x"})
    assert Repo.one(Call).status == "error"
  end
end
