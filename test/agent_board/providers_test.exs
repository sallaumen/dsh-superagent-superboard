defmodule AgentBoard.ProvidersTest do
  @moduledoc """
  Every catalog entry is a working configuration, not just a name.

  The live DeepSeek API is exercised elsewhere (scripts/eval-intake.sh); here
  each provider is driven through the same adapter with a stubbed endpoint, so
  a wrong base URL or a missing price shows up before anyone points a key at
  it.
  """
  use AgentBoard.DataCase, async: false

  alias AgentBoard.AI
  alias AgentBoard.AI.{Call, Providers}
  alias AgentBoard.Repo

  @stub AgentBoard.ProvidersTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :ai_api_key, "test-key")

    Application.put_env(:agent_board, :ai_client, fn ->
      Req.new(base_url: "https://stub", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Application.delete_env(:agent_board, :ai_client)
      Application.delete_env(:agent_board, :ai_api_key)
      Application.delete_env(:agent_board, :ai_provider)
    end)

    :ok
  end

  for provider <- [:deepseek, :gemini, :openai] do
    test "the #{provider} provider answers through the same adapter" do
      Application.put_env(:agent_board, :ai_provider, unquote(provider))

      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/chat/completions"

        Req.Test.json(conn, %{
          "model" => Providers.model(unquote(provider), :fast),
          "choices" => [%{"message" => %{"content" => ~s({"goal":"x"})}}],
          "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20}
        })
      end)

      assert {:ok, result} = AI.call(:refine_request, %{text: "x"})
      assert result.engine == unquote(provider)

      call = Repo.one(Call)
      assert call.engine == Atom.to_string(unquote(provider))
      assert call.cost_micros > 0
    end
  end

  test "every provider declares a price for both tiers" do
    for id <- Providers.ids() do
      {:ok, provider} = Providers.fetch(id)

      for tier <- [:fast, :deep] do
        assert Providers.cost_micros(id, Providers.model(id, tier), 1_000_000, 0) > 0
        assert Providers.cost_micros(id, Providers.model(id, tier), 0, 1_000_000) > 0
      end
    end
  end
end
