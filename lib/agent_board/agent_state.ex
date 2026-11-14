defmodule AgentBoard.AgentState do
  alias AgentBoard.{GitHub, Superagents}

  @moduledoc """
  The runner's state, read-only: the tickets, the heartbeat and the paths.

  The board never writes this database. It reads it to know what the executor
  is doing, and it keeps working when the file is absent or corrupt: the
  caller gets `{:error, reason}` and the UI marks that source unavailable.
  """

  @prod_default "/state/superagent/orchestrator.sqlite"

  @doc """
  The ticket databases the board reads: an explicit `:state_dbs` list, the
  single `:state_db`, or every local superagent profile (the two agents each
  have their own state directory), falling back to the production path.
  """
  @spec paths() :: [String.t()]
  def paths do
    case Application.get_env(:agent_board, :state_dbs) do
      [_ | _] = paths -> paths
      _ -> configured_paths()
    end
  end

  defp configured_paths do
    case Application.get_env(:agent_board, :state_db) do
      nil -> registered_or_fallback_paths()
      path -> [path]
    end
  end

  defp registered_or_fallback_paths do
    case Superagents.state_paths() do
      [] -> local_or_production_paths()
      dirs -> Enum.map(dirs, &Path.join(&1, "orchestrator.sqlite"))
    end
  rescue
    _exception -> local_or_production_paths()
  end

  defp local_or_production_paths do
    local = Path.wildcard(Path.expand("~/.dsh/state/superagent*/orchestrator.sqlite"))
    if local == [], do: [@prod_default], else: local
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
    results = Enum.map(paths(), &read_path/1)

    case Enum.filter(results, &match?({:ok, _}, &1)) do
      [] ->
        {:error, results |> Enum.map(&elem(&1, 1)) |> List.first()}

      successes ->
        {:ok,
         successes
         |> Enum.flat_map(fn {:ok, values} -> values end)
         |> Enum.flat_map(&decode/1)
         |> Enum.map(&normalize/1)}
    end
  end

  defp read_path(path) do
    with {:ok, conn} <- Exqlite.Sqlite3.open(path, mode: :readonly) do
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
    paths()
    |> Enum.flat_map(fn path -> [path <> "-wal", path] end)
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

  defp repository_from(urls) do
    Enum.find_value(urls, fn url ->
      case Regex.run(~r{^https://github\.com/([^/]+)/([^/]+)/(?:issues|pull|discussions)/}, url) do
        [_, owner, name] -> "#{owner}/#{name}"
        _ -> nil
      end
    end)
  end

  @doc """
  Whether a ticket belongs to this repository. A ticket with no URL keeps the
  old number-only behavior; a ticket that names another repository is not
  overlaid on this one.
  """
  @spec same_repository?(map(), map()) :: boolean()
  def same_repository?(ticket, repository) do
    case ticket["repository"] do
      nil -> true
      name -> String.downcase(name) == String.downcase("#{repository.owner}/#{repository.name}")
    end
  end

  @doc "The numbers a ticket maps to, from its mandate and channels."
  @spec ticket_numbers(map()) :: [integer()]
  def ticket_numbers(ticket) do
    scope = ticket |> nested(["mandate", "basis", "scope"]) |> object()
    base = scope["number"] |> GitHub.number() |> List.wrap()

    base ++
      (ticket
       |> channels()
       |> Enum.map(&GitHub.number(nested(&1, ["address", "number"])))
       |> Enum.reject(&is_nil/1))
  end

  @doc "The fields the board uses, with the runner's JSON kept intact."
  @spec normalize(map()) :: map()
  def normalize(ticket) do
    numbers = ticket_numbers(ticket)

    channel_urls =
      ticket
      |> channels()
      |> Enum.map(&nested(&1, ["address", "url"]))
      |> Enum.filter(&is_binary/1)

    last = ticket |> assignment_objects() |> List.last() |> object()
    report = object(last["report"])
    ended = object(ticket["ended"])

    %{
      "id" => ticket["id"],
      "numbers" => Enum.uniq(numbers),
      "assignment" => last["state"],
      "assignment_id" => last["id"],
      "report" => report["state"],
      "report_summary" => text(report["summary"]),
      "report_at" => parse(report["at"]),
      "started_at" => parse(last["startedAt"]),
      "idle_at" => parse(last["idleAt"]),
      "answered_at" => answered_at(ticket, last["id"]),
      "updated_at" => parse(ticket["updatedAt"]),
      "ended_outcome" => ended["outcome"],
      "ended_at" => parse(ended["at"]),
      "stopped" => ticket["stopped"] || false,
      "archived" => ticket["archived"] || false,
      "execution" => object(ticket["execution"]),
      "title" => text(ticket["title"]),
      "channel_urls" => channel_urls,
      "repository" => repository_from(channel_urls),
      "own_threads" => own_threads(ticket, numbers),
      "merged_threads" => merged_threads(ticket, numbers, ended),
      "reports" => reports(ticket),
      "assignments" => assignments(ticket)
    }
  end

  # When the worker of this Assignment last read a person's message: the
  # runner records each one in `inputs[]` (`kind: "trigger"`, `human: true`)
  # with the Assignment it was delivered to and the moment it was read. A
  # message not read yet, or one from a machine, is not an answer.
  defp answered_at(ticket, assignment_id) do
    ticket["inputs"]
    |> List.wrap()
    |> Enum.filter(
      &(is_map(&1) and &1["kind"] == "trigger" and &1["human"] == true and
          is_binary(assignment_id) and &1["deliveredTo"] == assignment_id)
    )
    |> Enum.map(&parse(&1["readAt"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  # Every Assignment in order, with its report and how it ended: the retry
  # policy counts the retries of a failure from them, and the detail lists
  # them as the attempts.
  defp assignments(ticket) do
    ticket
    |> assignment_objects()
    |> Enum.map(fn assignment ->
      report = object(assignment["report"])

      %{
        "id" => assignment["id"],
        "state" => assignment["state"],
        "report" => report["state"],
        "summary" => text(report["summary"]),
        "report_at" => parse(report["at"]),
        "created_at" => parse(assignment["createdAt"]),
        "started_at" => parse(assignment["startedAt"]),
        "ended_at" => parse(assignment["endedAt"]),
        "ended_reason" => assignment["endedReason"]
      }
    end)
  end

  # The GitHub threads the ticket opened itself (`follows` with `own`): the PR
  # it is waiting a review on. The issue it works for is a channel, not a
  # thread it owns, so it is left out even when the runner lists it.
  defp own_threads(ticket, numbers) do
    ticket["follows"]
    |> list()
    |> Enum.filter(&(is_map(&1) and &1["own"] == true))
    |> Enum.map(&thread_number(&1["thread"]))
    |> Enum.reject(&(is_nil(&1) or &1 in numbers))
    |> Enum.uniq()
  end

  # An older owned PR can also be closed. Only take the merge that ended
  # this ticket, never the latest number or a PR mentioned in the report.
  defp merged_threads(ticket, numbers, %{"outcome" => "merged", "at" => at}) do
    for %{"own" => true, "thread" => ref, "closed" => %{"outcome" => "merged", "at" => ^at}} <-
          list(ticket["follows"]),
        number = thread_number(ref),
        number not in numbers,
        uniq: true,
        do: number
  end

  defp merged_threads(_, _, _), do: []

  defp thread_number("github:" <> rest), do: GitHub.number(rest)
  defp thread_number(_other), do: nil

  defp reports(ticket) do
    ticket
    |> assignment_objects()
    |> Enum.flat_map(fn assignment ->
      case assignment["report"] do
        %{} = report ->
          [
            %{
              "state" => report["state"],
              "summary" => text(report["summary"]),
              "at" => parse(report["at"])
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp decode(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, ticket} when is_map(ticket) -> [ticket]
      _ -> []
    end
  end

  defp decode(_value), do: []

  # The runner owns this JSON and its shape moves with its version: a field in
  # another shape reads as absent, one row never fails every board load.
  defp channels(ticket), do: ticket["channels"] |> list() |> Enum.filter(&is_map/1)
  defp assignment_objects(ticket), do: ticket["assignments"] |> list() |> Enum.filter(&is_map/1)

  defp list(value) when is_list(value), do: value
  defp list(_value), do: []

  defp object(value) when is_map(value), do: value
  defp object(_value), do: %{}

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil

  defp nested(value, []), do: value
  defp nested(%{} = value, [key | keys]), do: nested(value[key], keys)
  defp nested(_value, _keys), do: nil

  defp read_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [value]} -> read_rows(conn, stmt, [value | acc])
      :done -> {:ok, Enum.reverse(acc)}
      other -> {:error, other}
    end
  end

  defp parse(nil), do: nil

  defp parse(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse(_value), do: nil
end
