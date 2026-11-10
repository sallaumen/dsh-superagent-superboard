defmodule AgentBoard.AITest do
  @moduledoc "A registered call runs, records its row, and refuses an unregistered name."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.AI
  alias AgentBoard.AI.{Cache, Call, Providers, Registry}
  alias AgentBoard.Repo

  @stub AgentBoard.AITest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :ai_api_key, "test-key")
    Application.put_env(:agent_board, :ai_provider, :deepseek)

    Application.put_env(:agent_board, :ai_client, fn ->
      Req.new(base_url: "https://api.deepseek.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Application.delete_env(:agent_board, :ai_client)
      Application.delete_env(:agent_board, :ai_api_key)
      Application.delete_env(:agent_board, :ai_provider)
    end)

    :ok
  end

  defp answer(content) do
    defaults = %{
      "constraints" => [],
      "non_goals" => [],
      "risks" => [],
      "blocking_questions" => [],
      "open_questions" => [],
      "assumptions" => [],
      "ready" => true,
      "language" => "pt"
    }

    content = defaults |> Map.merge(Jason.decode!(content)) |> Jason.encode!()

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
          ~s({"goal":"x","constraints":[],"non_goals":[],"risks":[],"blocking_questions":[],"open_questions":[],"language":"pt"})
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

  test "a paid response is not reported as success if its audit row cannot be stored" do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, :provider_answered)
      Req.Test.json(conn, answer(~s({"goal":"x"})))
    end)

    Repo.query!(
      "ALTER TABLE ai_calls ADD CONSTRAINT reject_ai_call_test CHECK (name <> 'refine_request')"
    )

    assert {:error, :audit_unavailable} = AI.call(:refine_request, %{text: "x"})
    assert_received :provider_answered
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

      assert payload["thinking"] == %{"type" => "disabled"}
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
                      ~s({"goal":"x","constraints":[],"non_goals":[],"risks":[],"blocking_questions":[],"open_questions":[],"assumptions":[],"ready":true,"language":"pt"})
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

  test "registered function schemas meet the strict object contract" do
    for name <- Registry.names() do
      {:ok, spec} = Registry.fetch(name)
      assert_strict_objects(spec.json_schema)
    end
  end

  defp assert_strict_objects(%{"type" => "object", "properties" => properties} = schema) do
    assert schema["additionalProperties"] == false
    assert MapSet.new(schema["required"]) == MapSet.new(Map.keys(properties))
    Enum.each(properties, fn {_name, child} -> assert_strict_objects(child) end)
  end

  defp assert_strict_objects(%{"type" => "array", "items" => child}),
    do: assert_strict_objects(child)

  defp assert_strict_objects(_schema), do: :ok

  test "DeepSeek's peak hours are its published ones, in UTC, on weekdays" do
    for {at, expected} <- [
          {~U[2026-11-10 00:59:59Z], false},
          {~U[2026-11-10 01:00:00Z], true},
          {~U[2026-11-10 03:59:59Z], true},
          {~U[2026-11-10 04:00:00Z], false},
          {~U[2026-11-10 05:59:59Z], false},
          {~U[2026-11-10 06:00:00Z], true},
          {~U[2026-11-10 09:59:59Z], true},
          {~U[2026-11-10 10:00:00Z], false},
          {~U[2026-11-07 07:00:00Z], false},
          {~U[2026-11-08 07:00:00Z], false},
          {~U[2026-11-13 07:00:00Z], true}
        ] do
      assert Providers.peak?(at) == expected, inspect(at)
    end
  end

  test "cost is computed from the model's price per million tokens" do
    # a Tuesday in DeepSeek's peak hours, and the same hour on a Saturday
    peak = ~U[2026-11-10 07:00:00Z]
    off_peak = ~U[2026-11-07 07:00:00Z]

    assert Providers.cost_micros(:deepseek, "deepseek-flash", 1_000_000, 0, peak) == 300_000
    assert Providers.cost_micros(:deepseek, "deepseek-flash", 0, 1_000_000, peak) == 1_200_000
    assert Providers.cost_micros(:deepseek, "deepseek-flash", 1_000, 2_000, peak) == 2_700
    assert Providers.cost_micros(:deepseek, "deepseek-flash", 1_000_000, 0, off_peak) == 150_000
    assert Providers.cost_micros(:deepseek, "deepseek-v4-pro", 0, 1_000_000, peak) == 3_960_000
    assert Providers.cost_micros(:deepseek, "not-a-model", 1_000, 1_000) == 0
    assert Providers.cost_micros(:nope, "x", 1_000, 1_000) == 0
  end

  test "a call records the cost the answer reports" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, answer(~s({"goal":"x"})))
    end)

    assert {:ok, _} = AI.call(:refine_request, %{text: "x"})
    call = Repo.one(Call)
    assert call.cost_micros > 0
  end

  test "a spent quota moves to the next provider with a key" do
    Application.delete_env(:agent_board, :ai_provider)
    Application.put_env(:agent_board, :ai_api_key, "test-key")

    {:ok, agent} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(@stub, fn conn ->
      attempt = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

      if attempt == 1 do
        Plug.Conn.send_resp(conn, 429, "spent")
      else
        Req.Test.json(conn, answer(~s({"goal":"x"})))
      end
    end)

    assert {:ok, _result} = AI.call(:refine_request, %{text: "x"})

    calls = Repo.all(Call)
    assert [first, second] = Enum.sort_by(calls, & &1.id)
    assert first.status == "error"
    assert second.status == "ok"
    refute first.engine == second.engine
  end

  test "an identical call is served from the cache" do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer(~s({"goal":"same"}))) end)

    assert {:ok, %{json: %{"goal" => "same"}}} = AI.call(:refine_request, %{text: "x"})
    assert Repo.aggregate(Call, :count) == 1

    assert {:ok, %{engine: :cache, json: %{"goal" => "same"}}} =
             AI.call(:refine_request, %{text: "x"})

    assert Repo.aggregate(Call, :count) == 1
  end

  test "a different input is a different cache key" do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer(~s({"goal":"same"}))) end)

    assert {:ok, _} = AI.call(:refine_request, %{text: "x"})
    assert {:ok, %{engine: :deepseek}} = AI.call(:refine_request, %{text: "y"})
    assert Repo.aggregate(Call, :count) == 2
  end

  test "a changed registered prompt or response contract invalidates the cache key" do
    {:ok, spec} = Registry.fetch(:refine_request)
    inputs = %{text: "same"}
    key = Cache.key(:refine_request, :deepseek, "deepseek-flash", inputs, spec)

    refute key ==
             Cache.key(:refine_request, :deepseek, "deepseek-flash", inputs, %{
               spec
               | system: spec.system <> " New rule."
             })

    refute key ==
             Cache.key(:refine_request, :deepseek, "deepseek-flash", inputs, %{
               spec
               | json_schema: Map.put(spec.json_schema, "additionalProperties", true)
             })
  end

  test "an old complete row with invalid JSON is not reused" do
    inputs = %{text: "x"}
    {:ok, spec} = Registry.fetch(:refine_request)

    %Call{}
    |> Call.changeset(%{
      name: "refine_request",
      engine: "deepseek",
      status: "ok",
      parse_state: "complete",
      input_hash: Cache.key(:refine_request, :deepseek, "deepseek-flash", inputs, spec),
      json: %{"goal" => "x", "constraints" => "not an array"}
    })
    |> Repo.insert!()

    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, answer(~s({"goal":"fresh"}))) end)

    assert {:ok, %{json: %{"goal" => "fresh"}, engine: :deepseek}} =
             AI.call(:refine_request, inputs)

    assert Repo.aggregate(Call, :count) == 2
  end

  test "an unregistered call is refused and records nothing" do
    assert {:error, :unknown_call} = AI.call(:nope, %{text: "x"})
    assert Repo.aggregate(Call, :count) == 0
  end

  test "valid JSON with a wrong field type is recorded as partial and never cached" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, answer(~s({"goal":"x","constraints":"not an array"})))
    end)

    assert {:error, :malformed_output} = AI.call(:refine_request, %{text: "x"})
    assert {:error, :malformed_output} = AI.call(:refine_request, %{text: "x"})

    assert [first, second] = Repo.all(Call) |> Enum.sort_by(& &1.id)

    for call <- [first, second] do
      assert call.status == "error"
      assert call.parse_state == "partial"
      assert call.error == "malformed_output"
      assert call.input_tokens == 10
      assert call.output_tokens == 20
      assert call.cost_micros > 0
    end
  end

  test "a failed call records the error" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, {:http, 500}} = AI.call(:refine_request, %{text: "x"})

    call = Repo.one(Call)
    assert call.status == "error"
    assert call.error =~ "500"
  end

  test "the unblock suggestion is registered and returns sendable options" do
    Application.put_env(:agent_board, :ai_rehearsal, true)
    on_exit(fn -> Application.delete_env(:agent_board, :ai_rehearsal) end)

    assert {:ok, %{json: %{"suggestions" => [_ | _] = suggestions}}} =
             AI.call(:suggest_unblock, %{
               question: "Entrego sem perfis?",
               blockage: "Falta o mapa"
             })

    assert Enum.all?(suggestions, &is_binary/1)
    assert Repo.one(Call).name == "suggest_unblock"
  end

  test "rehearsal answers without a key or a network" do
    Application.put_env(:agent_board, :ai_api_key, "")
    Application.put_env(:agent_board, :ai_rehearsal, true)
    on_exit(fn -> Application.delete_env(:agent_board, :ai_rehearsal) end)

    assert {:ok, result} = AI.call(:refine_request, %{text: "x"})
    assert AI.status() == :rehearsal
    assert result.engine == :rehearsal
    assert result.json["goal"] =~ "board"

    call = Repo.one(Call)
    assert call.engine == "rehearsal"
    assert call.status == "ok"
  end

  test "rehearsal needs no provider configured" do
    Application.delete_env(:agent_board, :ai_provider)
    Application.put_env(:agent_board, :ai_api_key, "")
    Application.put_env(:agent_board, :ai_rehearsal, true)
    on_exit(fn -> Application.delete_env(:agent_board, :ai_rehearsal) end)

    assert {:ok, result} = AI.call(:answer_question, %{question: "sem provider?"})
    assert AI.status() == :rehearsal
    assert result.engine == :rehearsal
    assert result.json["answer"] =~ "fixture"
  end

  test "a missing key is not a network call" do
    Application.put_env(:agent_board, :ai_api_key, "")

    assert {:error, :no_provider} = AI.call(:refine_request, %{text: "x"})
    # the attempt is still a row: it says the key was missing
    assert Repo.aggregate(Call, :count) == 1
  end
end
