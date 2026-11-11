defmodule AgentBoard.Orchestrator do
  @moduledoc """
  The runner's HTTP API: how many workers are running, how many tickets wait
  and the ceiling (`load.running`, `load.queued`, `maxWorkers`), and the one
  write the owner authorized, `retry/2` (see `AgentBoard.AutoRetry`).

  No call raises: an unreachable or unconfigured orchestrator answers
  `{:error, reason}` and the board shows `?` for the value, not a guess.
  """

  alias AgentBoard.Superagents

  @default_api "http://127.0.0.1:3082/orchestrator/api"

  @min_workers 1
  @max_workers 16

  @type load :: %{running: integer(), queued: integer(), max_workers: integer()}

  @doc "The current load, or the reason it is unknown."
  @spec load(Req.Request.t() | nil) :: {:ok, load()} | {:error, term()}
  def load(client \\ client())

  def load(nil), do: {:error, :not_configured}

  def load(client) do
    with {:ok, state} <- dispatch_state(client), do: {:ok, state.load}
  end

  @type dispatch_state :: %{repository: String.t() | nil, paused: boolean(), load: load()}

  @doc """
  What the router needs from the runner (`GET state`): the one repository
  it watches (`setup.accounts.repository`), whether it is paused, and the
  load. A repository the state does not name is `nil`, never a guess.
  """
  @spec dispatch_state(Req.Request.t() | nil) :: {:ok, dispatch_state()} | {:error, term()}
  def dispatch_state(client \\ client())

  def dispatch_state(nil), do: {:error, :not_configured}

  def dispatch_state(client) do
    case Req.get(client, url: "/state") do
      {:ok, %{status: 200, body: %{"load" => %{} = load} = body}} ->
        {:ok,
         %{
           repository: repository(get_in(body, ["setup", "accounts", "repository"])),
           paused: body["paused"] == true,
           load: %{
             running: int(load["running"]),
             queued: int(load["queued"]),
             max_workers: int(load["maxWorkers"])
           }
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

  @doc """
  Ask the runner to retry a ticket: `POST tickets/<id>/retry`, which ends
  the ticket's stalled Assignment and starts a new one.

  The runner refuses unless the ticket is open and its worker last reported
  `failed` or `blocked` with no person's message since (`canRetry` in
  `dsh: src/core/stage.ts`), so a retry can never start a second worker for
  one Assignment. A refusal is `{:refused, code}`; `:unreachable` means the
  request never connected; `:timeout` means it was sent and nobody knows
  whether it ran, which the next read of the runner's state settles.
  """
  @spec retry(Req.Request.t() | nil, String.t()) ::
          {:ok, :retried}
          | {:error,
             :not_configured
             | :unreachable
             | :timeout
             | :unknown_ticket
             | {:refused, String.t() | nil}
             | {:http, integer()}}
  def retry(nil, _ticket_id), do: {:error, :not_configured}

  def retry(client, ticket_id) when is_binary(ticket_id) do
    case Req.post(client,
           url: "/tickets/#{URI.encode(ticket_id, &URI.char_unreserved?/1)}/retry",
           json: %{},
           receive_timeout: 5_000
         ) do
      {:ok, %{status: 200}} -> {:ok, :retried}
      {:ok, %{status: 404}} -> {:error, :unknown_ticket}
      {:ok, %{status: 400, body: body}} -> {:error, {:refused, refusal(body)}}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, %{reason: :timeout}} -> {:error, :timeout}
      {:error, _exception} -> {:error, :unreachable}
    end
  rescue
    _exception -> {:error, :unreachable}
  end

  @doc """
  Set the runner's ceiling, `executor.maxWorkers`: read the executor block
  and its revision (`GET settings`), then save the whole block with the new
  ceiling at that revision (`PUT settings/executor`). A save in between is
  a `:conflict`, never an overwrite. Only the ceiling changes, so the runner
  does not restart; if it says it will (`restarting`), the answer says so.
  """
  @spec set_max_workers(Req.Request.t() | nil, integer()) ::
          {:ok, pos_integer()}
          | {:ok, pos_integer(), :restarting}
          | {:error,
             :not_configured
             | :out_of_range
             | :conflict
             | :malformed
             | :unreachable
             | :timeout
             | {:refused, String.t() | nil}
             | {:http, integer()}}
  def set_max_workers(nil, _max), do: {:error, :not_configured}

  def set_max_workers(_client, max)
      when not is_integer(max) or max < @min_workers or max > @max_workers,
      do: {:error, :out_of_range}

  def set_max_workers(client, max) do
    with {:ok, value, revision} <- executor_block(client) do
      save_executor(client, Map.put(value, "maxWorkers", max), revision, max)
    end
  rescue
    _exception -> {:error, :unreachable}
  end

  @doc "The runner's range for the ceiling (`dsh: src/limits.ts`)."
  @spec worker_range() :: Range.t()
  def worker_range, do: @min_workers..@max_workers

  defp executor_block(client) do
    case Req.get(client, url: "/settings", receive_timeout: 5_000) do
      {:ok,
       %{
         status: 200,
         body: %{"blocks" => %{"executor" => %{"value" => %{} = value, "revision" => revision}}}
       }}
      when is_integer(revision) ->
        {:ok, Map.delete(value, "paused"), revision}

      {:ok, %{status: 200}} ->
        {:error, :malformed}

      other ->
        failure(other)
    end
  end

  defp save_executor(client, value, revision, max) do
    case Req.put(client,
           url: "/settings/executor",
           json: %{value: value, revision: revision},
           receive_timeout: 5_000
         ) do
      {:ok, %{status: 200, body: %{"restarting" => true}}} -> {:ok, max, :restarting}
      {:ok, %{status: 200}} -> {:ok, max}
      {:ok, %{status: 409}} -> {:error, :conflict}
      {:ok, %{status: 400, body: body}} -> {:error, {:refused, refusal(body)}}
      other -> failure(other)
    end
  end

  defp failure({:ok, %{status: status}}), do: {:error, {:http, status}}
  defp failure({:error, %{reason: :timeout}}), do: {:error, :timeout}
  defp failure({:error, _exception}), do: {:error, :unreachable}

  defp refusal(%{"code" => code}) when is_binary(code), do: code
  defp refusal(%{"error" => message}) when is_binary(message), do: message
  defp refusal(_body), do: nil

  @doc "A client bound to the API, or nil when the API is switched off."
  def client do
    case Application.get_env(:agent_board, :orchestrator_client) do
      builder when is_function(builder, 0) -> builder.()
      _ -> build()
    end
  end

  @doc """
  The client of the agent that serves a repository (a struct or its id): its
  superagent's port, or the primary (`client/0`) when it has none.
  """
  @spec client_for(integer() | %{required(:id) => integer(), optional(atom()) => term()} | nil) ::
          Req.Request.t() | nil
  def client_for(repository) do
    case {client(), Superagents.get_by_repository(repository)} do
      {%Req.Request{} = client, %{port: port}} ->
        Req.merge(client, base_url: "http://127.0.0.1:#{port}/orchestrator/api")

      {client, _no_superagent} ->
        client
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

  @doc false
  # The orchestrator is local: a short connect timeout keeps a dead runner
  # from holding a board render. Public for the adapter of a registered
  # superagent (`DshManager`), which binds the same client to its port.
  def new(url) do
    Req.new(
      base_url: url,
      headers: [{"x-orchestrator-request", "1"}],
      retry: false,
      connect_options: [timeout: 500],
      receive_timeout: 1_000
    )
  end

  defp repository(value) when is_binary(value) and value != "", do: value
  defp repository(_value), do: nil

  defp int(value) when is_integer(value), do: value
  defp int(_value), do: 0
end
