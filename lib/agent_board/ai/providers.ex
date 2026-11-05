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
      models: %{fast: "deepseek-flash", deep: "deepseek-v4-pro"}
    },
    gemini: %{
      label: "Gemini",
      base_url: "https://generativelanguage.googleapis.com/v1beta/openai",
      key_env: "GEMINI_API_KEY",
      models: %{fast: "gemini-2.5-flash", deep: "gemini-2.5-pro"}
    },
    openai: %{
      label: "OpenAI",
      base_url: "https://api.openai.com/v1",
      key_env: "OPENAI_API_KEY",
      models: %{fast: "gpt-4.1-mini", deep: "gpt-4.1"}
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

  @doc "The first provider with a key, in order -- nil when none has one."
  @spec configured() :: id() | nil
  def configured, do: Enum.find(@order, &configured?/1)

  @spec configured?(atom()) :: boolean()
  def configured?(id), do: key(id) not in [nil, ""]
end
