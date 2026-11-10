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
      # US$ per 1M tokens at the peak rate, published at
      # https://api-docs.deepseek.com/quick_start/pricing (read 2026-11-10).
      # `input` is a cache miss; off-peak hours pay `off_peak` of these.
      prices: %{
        fast: %{input: 0.30, output: 1.20, cache_read: 0.006, off_peak: 0.5},
        deep: %{input: 1.32, output: 3.96, cache_read: 0.044, off_peak: 0.5}
      }
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
  free. `:off_peak` is the share of these prices a token pays outside the
  provider's peak hours (`peak?/1`, `at_full_rate/3`). Nil for a model the
  catalog does not list.
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

  @doc """
  The provider's own key, from its environment variable. `:ai_api_key` is a
  test override standing for every provider's key; no config sets it, since it
  would send one provider's key to all of them.
  """
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
  Whether an instant (UTC) is in DeepSeek's peak hours: 01:00 to 04:00 and
  06:00 to 10:00, Monday to Friday. The provider also treats Chinese public
  holidays as off-peak; the board has no such calendar and prices them as
  peak, so on those days the estimate is high.
  """
  @spec peak?(DateTime.t()) :: boolean()
  def peak?(%DateTime{hour: hour} = at),
    do: Date.day_of_week(at) <= 5 and (hour in 1..3 or hour in 6..9)

  @doc """
  How many tokens at the published price these are worth: those of the peak
  hours count whole, the others by the model's `:off_peak` share. A price
  table without one has a single rate.
  """
  @spec at_full_rate(number(), number(), map()) :: number()
  def at_full_rate(tokens, peak_tokens, %{off_peak: share}) when is_number(share),
    do: peak_tokens + (tokens - peak_tokens) * share

  def at_full_rate(tokens, _peak_tokens, _prices), do: tokens

  @doc """
  The cost of a call in microdollars, from the model's published price per
  million tokens at the instant of the call. An unknown model or a provider
  with no price table answers zero rather than guessing -- a wrong number in
  the panel is worse than no number.
  """
  @spec cost_micros(atom(), String.t() | nil, non_neg_integer(), non_neg_integer(), DateTime.t()) ::
          non_neg_integer()
  def cost_micros(provider, model, input_tokens, output_tokens, at \\ DateTime.utc_now()) do
    with {:ok, %{models: models, prices: prices}} <- fetch(provider),
         {tier, ^model} <- Enum.find(models, fn {_tier, id} -> id == model end),
         %{input: input_price, output: output_price} = price <- Map.get(prices, tier) do
      peak? = peak?(at)
      input = at_full_rate(input_tokens, if(peak?, do: input_tokens, else: 0), price)
      output = at_full_rate(output_tokens, if(peak?, do: output_tokens, else: 0), price)
      round(input * input_price + output * output_price)
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
