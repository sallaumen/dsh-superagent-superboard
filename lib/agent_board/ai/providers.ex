defmodule AgentBoard.AI.Providers do
  @moduledoc """
  The provider catalog: one declaration per OpenAI-compatible engine.

  DeepSeek, Gemini's compatibility endpoint, OpenAI and anything else that
  speaks /chat/completions with a Bearer key share one adapter. Adding a
  provider is a map entry, not a module.
  """

  @type id :: :deepseek | :gemini | :openai

  @providers %{
    deepseek: %{
      label: "DeepSeek",
      base_url: "https://api.deepseek.com",
      key_env: "DEEPSEEK_API_KEY",
      models: %{fast: "deepseek-flash", deep: "deepseek-v4-pro"},
      prices: %{fast: %{input: 0.28, output: 0.42}, deep: %{input: 0.28, output: 0.42}}
    },
    gemini: %{
      label: "Gemini",
      base_url: "https://generativelanguage.googleapis.com/v1beta/openai",
      key_env: "GEMINI_API_KEY",
      models: %{fast: "gemini-2.5-flash", deep: "gemini-2.5-pro"},
      prices: %{fast: %{input: 0.30, output: 2.50}, deep: %{input: 1.25, output: 10.00}}
    },
    openai: %{
      label: "OpenAI",
      base_url: "https://api.openai.com/v1",
      key_env: "OPENAI_API_KEY",
      models: %{fast: "gpt-4.1-mini", deep: "gpt-4.1"},
      prices: %{fast: %{input: 0.40, output: 1.60}, deep: %{input: 2.00, output: 8.00}}
    }
  }

  @order [:deepseek, :gemini, :openai]

  @spec ids() :: [id()]
  def ids, do: @order

  @spec all() :: [{id(), map()}]
  def all, do: Enum.map(@order, &{&1, Map.fetch!(@providers, &1)})

  @spec fetch(atom()) :: {:ok, map()} | :error
  def fetch(id), do: Map.fetch(@providers, id)

  @doc "The model for a tier, falling back to the provider's fast model."
  @spec model(atom(), atom()) :: String.t() | nil
  def model(id, tier) do
    case fetch(id) do
      {:ok, %{models: models}} -> Map.get(models, tier) || models.fast
      :error -> nil
    end
  end

  @doc """
  The price table of the tier that serves `model`, whatever the provider:
  the coding agent's harness names its provider differently (DeepSeek's is
  `deepseek-account`), but the model id is the same. `:cache_read` and
  `:cache_write` are optional; a token kind without a price is unpriced, not
  free. Nil for a model the catalog does not list.
  """
  @spec prices_for_model(String.t() | nil) :: map() | nil
  def prices_for_model(nil), do: nil

  def prices_for_model(model) do
    Enum.find_value(@providers, fn {_id, provider} -> tier_prices(provider, model) end)
  end

  defp tier_prices(%{models: models, prices: prices}, model) do
    case Enum.find(models, fn {_tier, id} -> id == model end) do
      {tier, _id} -> Map.get(prices, tier)
      nil -> nil
    end
  end

  @doc "The key, from the panel config first, then the environment."
  @spec key(atom()) :: String.t()
  def key(id) do
    case fetch(id) do
      {:ok, %{key_env: env}} ->
        Application.get_env(:agent_board, :ai_api_key) || System.get_env(env, "")

      :error ->
        ""
    end
  end

  @doc """
  The cost of a call in microdollars, from the model's published price per
  million tokens. An unknown model or a provider with no price table answers
  zero rather than guessing -- a wrong number in the panel is worse than no
  number.
  """
  @spec cost_micros(atom(), String.t() | nil, non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def cost_micros(provider, model, input_tokens, output_tokens) do
    with {:ok, %{models: models, prices: prices}} <- fetch(provider),
         {tier, ^model} <- Enum.find(models, fn {_tier, id} -> id == model end),
         %{input: input_price, output: output_price} <- Map.get(prices, tier) do
      round(input_tokens * input_price + output_tokens * output_price)
    else
      _ -> 0
    end
  end

  @doc "The first provider with a key, in order -- nil when none has one."
  @spec configured() :: id() | nil
  def configured, do: Enum.find(@order, &configured?/1)

  @spec configured?(atom()) :: boolean()
  def configured?(id), do: key(id) not in [nil, ""]
end
