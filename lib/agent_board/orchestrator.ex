defmodule AgentBoard.Orchestrator do
  @moduledoc """
  The runner's HTTP API, read-only: how many workers are running, how many
  tickets wait and the ceiling (`load.running`, `load.queued`, `maxWorkers`).

  The call never raises: an unreachable or unconfigured orchestrator answers
  `{:error, reason}` and the board shows `?` for the value, not a guess.
  """

  @default_api "http://127.0.0.1:3082/orchestrator/api"

  @type load :: %{running: integer(), queued: integer(), max_workers: integer()}

  @doc "The current load, or the reason it is unknown."
  @spec load(Req.Request.t() | nil) :: {:ok, load()} | {:error, term()}
  def load(client \\ client())

  def load(nil), do: {:error, :not_configured}

  def load(client) do
    case Req.get(client, url: "/state") do
      {:ok, %{status: 200, body: %{"load" => %{} = load}}} ->
        {:ok,
         %{
           running: int(load["running"]),
           queued: int(load["queued"]),
           max_workers: int(load["maxWorkers"])
         }}

      {:ok, %{status: 200}} ->
        {:error, :malformed}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, _exception} ->
        {:error, :unreachable}
    end
  rescue
    _exception -> {:error, :unreachable}
  end

  @doc "A client bound to the API, or nil when the API is switched off."
  def client do
    case Application.get_env(:agent_board, :orchestrator_client) do
      builder when is_function(builder, 0) -> builder.()
      _ -> build()
    end
  end

  @doc false
  def build do
    case Application.get_env(:agent_board, :orchestrator_api, System.get_env("SUPERAGENT_API")) do
      false ->
        nil

      url when is_binary(url) and url != "" ->
        new(url)

      _ ->
        new(@default_api)
    end
  end

  # The orchestrator is local: a short connect timeout keeps a dead runner
  # from holding a board render.
  defp new(url) do
    Req.new(
      base_url: url,
      headers: [{"x-orchestrator-request", "1"}],
      retry: false,
      connect_options: [timeout: 500],
      receive_timeout: 1_000
    )
  end

  defp int(value) when is_integer(value), do: value
  defp int(_value), do: 0
end
