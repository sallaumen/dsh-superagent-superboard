defmodule AgentBoard.Superagents.DshManager do
  @moduledoc """
  Real adapter for `dsh-superagent`: the management API for status/pause/scale
  and the manager script for start/stop. Commands run with an argument list,
  never a shell string; credentials stay in the DSH environment.
  """
  @behaviour AgentBoard.Superagents.Manager

  alias AgentBoard.Orchestrator
  alias AgentBoard.Superagents.{Prototype, Superagent}

  @doc """
  The manager script; `:superagent_manager_script` or `DSH_SUPERAGENT_MANAGER`
  wins, else the one in the agent's code on this machine (`Prototype`).
  """
  def script do
    Application.get_env(:agent_board, :superagent_manager_script) ||
      System.get_env("DSH_SUPERAGENT_MANAGER") || Prototype.manager()
  end

  @impl true
  def status(%Superagent{} = superagent) do
    case get(superagent, "/state") do
      {:ok, 200, body} -> {:ok, observation(body)}
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def identity(%Superagent{} = superagent) do
    case get(superagent, "/state") do
      {:ok, 200, %{} = body} ->
        accounts = get_in(body, ["setup", "accounts"])
        accounts = if is_map(accounts), do: accounts, else: %{}

        {:ok,
         %{
           repository: text(accounts["repository"]),
           bot: text(accounts["agent"]),
           max_workers: workers(get_in(body, ["load", "maxWorkers"]))
         }}

      {:ok, status, _body} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

  defp workers(value) when is_integer(value) and value > 0, do: value
  defp workers(_value), do: nil

  @impl true
  def start(%Superagent{} = superagent), do: manager(superagent, "start")
  @impl true
  def stop(%Superagent{} = superagent), do: manager(superagent, "stop")

  @impl true
  def pause(%Superagent{} = superagent, paused) when is_boolean(paused) do
    case post(superagent, "/executor/pause", %{"paused" => paused}) do
      {:ok, 200, _body} -> :ok
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # One writer of `executor.maxWorkers`: the Orchestrator's read-block,
  # PUT-at-revision call, bound to this agent's port. A save in between is a
  # `:conflict` here too, never an overwrite.
  @impl true
  def scale(%Superagent{} = superagent, workers) when is_integer(workers) and workers > 0 do
    case Orchestrator.set_max_workers(Orchestrator.new(url(superagent)), workers) do
      {:ok, _max} -> :ok
      {:ok, _max, :restarting} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def access(%Superagent{} = superagent) do
    with {:ok, 200, settings} <- get(superagent, "/settings"),
         {:ok, value, _revision} <- policy_block(settings),
         {:ok, entries} <- allowed_entries(value) do
      {:ok, %{allowed: Enum.flat_map(entries, &allowed_person/1)}}
    else
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def allow(%Superagent{} = superagent, login) when is_binary(login) do
    edit_allowed(superagent, fn entries ->
      if Enum.any?(entries, &same_login?(&1, login)),
        do: entries,
        else: entries ++ [%{"id" => login}]
    end)
  end

  @impl true
  def disallow(%Superagent{} = superagent, login) when is_binary(login) do
    edit_allowed(superagent, fn entries -> Enum.reject(entries, &same_login?(&1, login)) end)
  end

  @impl true
  def requeue(%Superagent{} = superagent, trigger_id) when is_binary(trigger_id) do
    id = URI.encode(trigger_id, &URI.char_unreserved?/1)

    case post(superagent, "/triggers/#{id}/requeue", %{}) do
      {:ok, 200, %{"queued" => queued}} when is_boolean(queued) -> {:ok, queued}
      {:ok, 200, _body} -> {:error, :malformed}
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Read the whole block and save it back at the revision it was read, so a
  # change made elsewhere in between is a conflict, never an overwrite, and
  # everything but the list stays exactly as the agent had it.
  defp edit_allowed(superagent, change) do
    with {:ok, 200, settings} <- get(superagent, "/settings"),
         {:ok, value, revision} <- policy_block(settings),
         {:ok, entries} <- allowed_entries(value) do
      case change.(entries) do
        ^entries -> :ok
        next -> save_allowed(superagent, value, revision, next)
      end
    else
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp save_allowed(superagent, value, revision, entries) do
    body = %{
      "value" => put_in(value, ["sources", "github", "allowed"], entries),
      "revision" => revision
    }

    case put(superagent, "/settings/policy", body) do
      {:ok, 200, _body} -> :ok
      {:ok, 409, _body} -> {:error, :conflict}
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp policy_block(%{"blocks" => %{"policy" => %{"value" => value, "revision" => revision}}})
       when is_map(value) and is_integer(revision),
       do: {:ok, value, revision}

  defp policy_block(_settings), do: {:error, :malformed}

  defp allowed_entries(%{"sources" => %{"github" => %{"allowed" => entries}}})
       when is_list(entries),
       do: {:ok, entries}

  defp allowed_entries(_value), do: {:error, :github_source_missing}

  defp allowed_person(%{"id" => login} = entry) when is_binary(login),
    do: [%{login: login, name: entry["name"]}]

  defp allowed_person(_entry), do: []

  defp same_login?(%{"id" => id}, login) when is_binary(id),
    do: String.downcase(id) == String.downcase(login)

  defp same_login?(_entry, _login), do: false

  defp manager(superagent, command) do
    args = ["--profile", superagent.profile, "--url", origin(superagent), command]

    opts = [stderr_to_stdout: true, env: manager_env(superagent.profile)]

    case System.cmd("python3", [script() | args], opts) do
      {_output, 0} ->
        :ok

      {output, code} ->
        if command == "start" and String.contains?(output, "Startup health check timed out"),
          do: :ok,
          else: {:error, {:manager, code, String.slice(output, 0, 500)}}
    end
  rescue
    exception -> {:error, exception}
  end

  defp manager_env(profile) do
    env = [{"GH_TOKEN", nil}, {"GITHUB_TOKEN", nil}]
    bin = Path.join([System.user_home!(), ".local/share/superboard/runtimes/profiles", profile])

    if Regex.match?(~r/\A[a-zA-Z0-9_][\w.-]*\z/, profile) and File.regular?(Path.join(bin, "dsh")),
      do: [{"PATH", bin <> ":" <> System.get_env("PATH", "")} | env],
      else: env
  end

  @doc false
  # Public for the tests. The manager's answer is outside data, read in a task
  # linked to the ticker: a shape this does not expect is an observed error.
  def observation(body) when is_map(body) do
    health = if is_map(body["health"]), do: body["health"], else: %{}
    setup = body["setup"]
    load = body["load"] || %{}
    paused = body["paused"] == true
    errors = health_errors(health)

    cond do
      setup_detail(setup) ->
        %{state: "error", detail: setup_detail(setup), load: load, paused: paused, setup: setup}

      errors != [] ->
        %{state: "error", detail: Enum.join(errors, "; "), load: load, paused: paused}

      true ->
        runtime_observation(health, load, paused)
    end
  end

  def observation(_body),
    do: %{state: "error", detail: "unexpected answer from the manager", load: %{}, paused: false}

  defp health_errors(health) do
    health
    |> Enum.filter(fn {_name, entry} -> is_map(entry) and entry["state"] == "error" end)
    |> Enum.map(fn {name, entry} -> "#{name}: #{entry["detail"]}" end)
  end

  defp setup_detail(%{"problem" => %{"detail" => detail}}) when is_binary(detail), do: detail
  defp setup_detail(%{"detail" => detail}) when is_binary(detail), do: detail
  defp setup_detail(_setup), do: nil

  defp runtime_state(%{"runtime" => %{"state" => state}}), do: state
  defp runtime_state(_health), do: nil

  defp runtime_observation(health, load, paused) do
    case {paused, runtime_state(health)} do
      {true, _} -> %{state: "paused", detail: nil, load: load, paused: true}
      {false, "paused"} -> %{state: "paused", detail: nil, load: load, paused: true}
      {false, "starting"} -> %{state: "starting", detail: nil, load: load, paused: false}
      {false, "ready"} -> %{state: "ready", detail: nil, load: load, paused: false}
      _ -> %{state: "error", detail: "runtime is not ready", load: load, paused: paused}
    end
  end

  @impl true
  def prompts(%Superagent{} = superagent) do
    case get(superagent, "/prompts") do
      {:ok, 200, %{"current" => %{"revision" => revision, "config" => %{} = config}}}
      when is_integer(revision) ->
        {:ok, %{revision: revision, config: config}}

      {:ok, 200, _body} ->
        {:error, :prompts_missing}

      {:ok, status, _body} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The orchestrator refuses a `baseRevision` that is no longer the current
  # one: whoever saved in between (the dsh panel) is not overwritten.
  @impl true
  def save_prompts(%Superagent{} = superagent, %{} = config, base_revision) do
    case put(superagent, "/prompts", %{"config" => config, "baseRevision" => base_revision}) do
      {:ok, 200, %{"revision" => revision}} when is_integer(revision) -> {:ok, revision}
      {:ok, 409, _body} -> {:error, :conflict}
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get(superagent, path), do: request(superagent, :get, path, nil)
  defp post(superagent, path, body), do: request(superagent, :post, path, body)
  defp put(superagent, path, body), do: request(superagent, :put, path, body)

  defp request(superagent, method, path, body) do
    opts = [
      url: url(superagent) <> path,
      headers: [{"x-orchestrator-request", "1"}],
      receive_timeout: 4_000,
      retry: false
    ]

    opts = if body, do: Keyword.put(opts, :json, body), else: opts

    Req.request([method: method] ++ opts)
    |> case do
      {:ok, %{status: status, body: body}} -> {:ok, status, body}
      {:error, exception} -> {:error, exception}
    end
  end

  defp origin(superagent), do: "http://127.0.0.1:#{superagent.port}"
  defp url(superagent), do: origin(superagent) <> "/orchestrator/api"
end
