defmodule AgentBoard.AgentState do
  @moduledoc """
  The runner's state, read-only: the tickets, the heartbeat and the paths.

  The board never writes this database. It reads it to know what the executor
  is doing, and it keeps working when the file is absent or corrupt: the
  caller gets `{:error, reason}` and the UI marks that source unavailable.
  """

  @local_default Path.expand("~/.dsh/state/superagent/orchestrator.sqlite")
  @prod_default "/state/superagent/orchestrator.sqlite"

  @doc """
  The ticket database path.

  An explicit `:state_db` config wins (the tests use it). Otherwise the local
  runner path is used when it exists, so a development checkout reads the
  agent it actually has; the production path is the fallback.
  """
  @spec path() :: String.t()
  def path do
    Application.get_env(:agent_board, :state_db) ||
      if(File.exists?(@local_default), do: @local_default, else: @prod_default)
  end

  @doc "Every ticket, normalized for the board. A read failure reads as no tickets."
  @spec tickets() :: [map()]
  def tickets do
    case read_normalized() do
      {:ok, tickets} -> tickets
      {:error, _reason} -> []
    end
  end

  @doc "The normalized tickets and the read outcome, for the freshness snapshot."
  @spec read_normalized() :: {:ok, [map()]} | {:error, term()}
  def read_normalized do
    case read() do
      {:ok, values} -> {:ok, values |> Enum.flat_map(&decode/1) |> Enum.map(&normalize/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The raw JSON values in the ticket table."
  @spec read() :: {:ok, [String.t()]} | {:error, term()}
  def read do
    with {:ok, conn} <- Exqlite.Sqlite3.open(path()) do
      try do
        with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, "SELECT value FROM ticket"),
             {:ok, rows} <- read_rows(conn, stmt, []) do
          Exqlite.Sqlite3.release(conn, stmt)
          {:ok, rows}
        end
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  @doc """
  The last time the runner wrote its state.

  The sqlite WAL is the heartbeat: the orchestrator touches it while it works,
  so a fresh mtime is evidence that the process is alive even when no ticket
  changed. An absent file answers `nil`.
  """
  @spec heartbeat_at() :: DateTime.t() | nil
  def heartbeat_at do
    [path() <> "-wal", path()]
    |> Enum.flat_map(fn file ->
      case File.stat(file, time: :posix) do
        {:ok, %File.Stat{mtime: mtime}} -> [mtime]
        _ -> []
      end
    end)
    |> Enum.max(fn -> nil end)
    |> case do
      nil -> nil
      posix -> DateTime.from_unix!(posix)
    end
  end

  @doc """
  One read for the board: whether the source answered, when it last wrote and
  the normalized tickets. `ok` describes the read, not the work.
  """
  @spec snapshot() :: %{
          ok: boolean(),
          at: DateTime.t() | nil,
          tickets: [map()],
          error: term() | nil
        }
  def snapshot do
    case read_normalized() do
      {:ok, tickets} ->
        %{
          ok: true,
          at: heartbeat_at() || latest_updated_at(tickets),
          tickets: tickets,
          error: nil
        }

      {:error, reason} ->
        %{ok: false, at: nil, tickets: [], error: reason}
    end
  end

  @doc "The newest ticket update, or nil when the table is empty."
  @spec latest_updated_at([map()]) :: DateTime.t() | nil
  def latest_updated_at(tickets) do
    tickets
    |> Enum.map(& &1["updated_at"])
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  @doc "The numbers a ticket maps to, from its mandate and channels."
  @spec ticket_numbers(map()) :: [integer()]
  def ticket_numbers(ticket) do
    scope = get_in(ticket, ["mandate", "basis", "scope"]) || %{}
    base = if is_integer(scope["number"]), do: [scope["number"]], else: []

    # The parens matter: |> binds tighter than ||, so without them the
    # pipeline would apply only to the [] fallback and leave the real channel
    # entries unmapped (numbers as maps instead of integers).
    base ++
      ((ticket["channels"] || [])
       |> Enum.map(&to_int(get_in(&1, ["address", "number"])))
       |> Enum.reject(&is_nil/1))
  end

  @doc "The fields the board uses, with the runner's JSON kept intact."
  @spec normalize(map()) :: map()
  def normalize(ticket) do
    numbers = ticket_numbers(ticket)
    last = List.last(ticket["assignments"] || []) || %{}
    report = last["report"] || %{}
    ended = ticket["ended"] || %{}

    %{
      "numbers" => Enum.uniq(numbers),
      "assignment" => last["state"],
      "report" => report["state"],
      "report_summary" => report["summary"],
      "report_at" => parse(report["at"]),
      "started_at" => parse(last["startedAt"]),
      "idle_at" => parse(last["idleAt"]),
      "updated_at" => parse(ticket["updatedAt"]),
      "ended_outcome" => ended["outcome"],
      "ended_at" => parse(ended["at"]),
      "stopped" => ticket["stopped"] || false,
      "archived" => ticket["archived"] || false,
      "execution" => ticket["execution"] || %{},
      "title" => ticket["title"],
      "channel_urls" =>
        (ticket["channels"] || [])
        |> Enum.map(&get_in(&1, ["address", "url"]))
        |> Enum.filter(&is_binary/1),
      "own_threads" => own_threads(ticket, numbers),
      "reports" => reports(ticket)
    }
  end

  # The GitHub threads the ticket opened itself (`follows` with `own`): the PR
  # it is waiting a review on. The issue it works for is a channel, not a
  # thread it owns, so it is left out even when the runner lists it.
  defp own_threads(ticket, numbers) do
    (ticket["follows"] || [])
    |> Enum.filter(&(is_map(&1) and &1["own"] == true))
    |> Enum.map(&thread_number(&1["thread"]))
    |> Enum.reject(&(is_nil(&1) or &1 in numbers))
    |> Enum.uniq()
  end

  defp thread_number("github:" <> rest) do
    case Integer.parse(rest) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp thread_number(_other), do: nil

  defp reports(ticket) do
    (ticket["assignments"] || [])
    |> Enum.flat_map(fn assignment ->
      case assignment["report"] do
        %{} = report ->
          [
            %{
              "state" => report["state"],
              "summary" => report["summary"],
              "at" => parse(report["at"])
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp decode(value) do
    case Jason.decode(value) do
      {:ok, ticket} when is_map(ticket) -> [ticket]
      _ -> []
    end
  end

  defp read_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [value]} -> read_rows(conn, stmt, [value | acc])
      :done -> {:ok, Enum.reverse(acc)}
      other -> {:error, other}
    end
  end

  defp to_int(nil), do: nil
  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s), do: String.to_integer(s)
  defp to_int(_), do: nil

  defp parse(nil), do: nil

  defp parse(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse(_value), do: nil
end
