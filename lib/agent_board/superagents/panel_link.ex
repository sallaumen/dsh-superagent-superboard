defmodule AgentBoard.Superagents.PanelLink do
  @moduledoc """
  The address that opens an agent's dsh panel signed in.

  dsh answers "authentication required" to a browser that never opened the
  address it printed at start: that address carries the process's launch
  token, and opening it once leaves a cookie. The manager writes the line
  `dsh web: <address>` in the agent's log
  (`<DSH_SUPERAGENT_HOME>/.artifacts/dsh-superagent-<profile>-<stamp>.log`);
  `scripts/agent/panel.sh` reads the same line.

  The address is a credential. `url/1` hands it only to the controller that
  redirects a browser on this machine to it; it is never rendered, logged or
  stored. An address that is not this agent's own panel on this machine
  (`http://127.0.0.1:<its port>/`) is refused: a log is outside data, and
  the board never sends a browser anywhere else.
  """

  alias AgentBoard.Superagents.Superagent

  @default_home "~/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype"

  @type reason :: {:unreadable, File.posix()} | :no_log | :no_address | :foreign

  @spec url(Superagent.t()) :: {:ok, String.t()} | {:error, reason()}
  def url(%Superagent{profile: profile, port: port}) do
    dir = Path.join(home(), ".artifacts")

    with {:ok, names} <- list(dir),
         {:ok, log} <- newest(dir, names, profile),
         {:ok, address} <- address(log) do
      own(address, port)
    end
  end

  defp home do
    Application.get_env(:agent_board, :dsh_superagent_home) ||
      System.get_env("DSH_SUPERAGENT_HOME") || Path.expand(@default_home)
  end

  defp list(dir) do
    case File.ls(dir) do
      {:ok, names} -> {:ok, names}
      {:error, :enoent} -> {:error, :no_log}
      {:error, reason} -> {:error, {:unreadable, reason}}
    end
  end

  # The digit keeps "superagent" from matching the logs of "superagent-colmex".
  defp newest(dir, names, profile) do
    pattern = ~r/\Adsh-superagent-#{Regex.escape(profile)}-\d.*\.log\z/

    names
    |> Enum.filter(&Regex.match?(pattern, &1))
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.max_by(&modified/1, fn -> nil end)
    |> case do
      nil -> {:error, :no_log}
      log -> {:ok, log}
    end
  end

  defp modified(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _reason} -> 0
    end
  end

  # The last line wins: a restart prints a new token in the same log.
  defp address(log) do
    log
    |> File.stream!()
    |> Enum.reduce(nil, fn
      "dsh web: " <> address, _last -> String.trim(address)
      _line, last -> last
    end)
    |> case do
      nil -> {:error, :no_address}
      "" -> {:error, :no_address}
      address -> {:ok, address}
    end
  rescue
    error in File.Error -> {:error, {:unreadable, error.reason}}
  end

  defp own(address, port) do
    case URI.parse(address) do
      %URI{scheme: "http", host: host, port: ^port} when host in ["127.0.0.1", "localhost"] ->
        {:ok, address}

      _other ->
        {:error, :foreign}
    end
  end
end
