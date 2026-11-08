defmodule AgentBoard.Superagents.DshManager do
  @moduledoc """
  Real adapter for `dsh-superagent`: the management API for status/pause/scale
  and the manager script for start/stop. Commands run with an argument list,
  never a shell string; credentials stay in the DSH environment.
  """
  @behaviour AgentBoard.Superagents.Manager

  alias AgentBoard.Superagents.Superagent

  @default_script Path.expand(
                    "~/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype/scripts/dsh-superagent"
                  )

  @doc "The manager script; `:superagent_manager_script` or `DSH_SUPERAGENT_MANAGER` wins."
  def script do
    Application.get_env(:agent_board, :superagent_manager_script) ||
      System.get_env("DSH_SUPERAGENT_MANAGER") || @default_script
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

  @impl true
  def scale(%Superagent{} = superagent, workers) when is_integer(workers) and workers > 0 do
    with {:ok, 200, settings} <- get(superagent, "/settings"),
         %{"value" => value, "revision" => revision} <- get_in(settings, ["blocks", "executor"]),
         value = Map.put(value, "maxWorkers", workers),
         {:ok, 200, _body} <-
           put(superagent, "/settings/executor", %{"value" => value, "revision" => revision}) do
      :ok
    else
      {:ok, status, _body} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp manager(superagent, command) do
    args = ["--profile", superagent.profile, "--url", url(superagent), command]

    case System.cmd("python3", [script() | args], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> {:error, {:manager, code, String.slice(output, 0, 500)}}
    end
  rescue
    exception -> {:error, exception}
  end

  defp observation(body) do
    health = body["health"] || %{}
    setup = body["setup"]
    load = body["load"] || %{}
    paused = body["paused"] == true
    errors = health_errors(health)

    cond do
      is_map(setup) and setup["detail"] ->
        %{state: "error", detail: setup["detail"], load: load, paused: paused, setup: setup}

      errors != [] ->
        %{state: "error", detail: Enum.join(errors, "; "), load: load, paused: paused}

      true ->
        runtime_observation(health, load, paused)
    end
  end

  defp health_errors(health) do
    health
    |> Enum.filter(fn {_name, entry} -> entry["state"] == "error" end)
    |> Enum.map(fn {name, entry} -> "#{name}: #{entry["detail"]}" end)
  end

  defp runtime_observation(health, load, paused) do
    case {paused, get_in(health, ["runtime", "state"])} do
      {true, _} -> %{state: "paused", detail: nil, load: load, paused: true}
      {false, "paused"} -> %{state: "paused", detail: nil, load: load, paused: true}
      {false, "starting"} -> %{state: "starting", detail: nil, load: load, paused: false}
      {false, "ready"} -> %{state: "ready", detail: nil, load: load, paused: false}
      _ -> %{state: "error", detail: "runtime não está pronto", load: load, paused: paused}
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

  defp url(superagent), do: "http://127.0.0.1:#{superagent.port}/orchestrator/api"
end
