defmodule AgentBoard.Superagents.Leftovers do
  @moduledoc """
  What ended tickets leave on the disk, and how long it stays.

  A `dsh-superagent` never deletes anything: each ticket keeps its folder (a
  git worktree with its build) under `<state>/work/`, and a ticket that ended
  without a merge can keep its pull request open. The folders are the cost: a
  busy agent writes gigabytes a day. The history is not in them: the ticket,
  its issue, its pull request and its branch stay wherever this module runs.

  The rules of what may go are `scripts/agent/cleanup.sh`, which this module
  runs and reads: never an open ticket, never a folder with uncommitted
  changes (it has no `--force` here), never a pull request someone else
  opened.

    * `survey/1` is the dry run: what could go now, and how much it weighs.
    * Each project keeps its ended folders for `days/1` days (30 by default,
      or `:never`). `sweep/0` removes the older ones, folders only, through
      the action `:sweep_agent_folders`; the board calls it once a day.
    * `clean/2` with `:all` is the owner's red button: every ended folder and
      the orphan pull requests.
  """
  require Logger

  alias AgentBoard.{Actions, Settings, Superagents}
  alias AgentBoard.Superagents.Superagent

  @script Path.expand("../../../scripts/agent/cleanup.sh", __DIR__)
  @choices [7, 14, 30, 60]
  @default 30

  @type folder :: %{name: String.t(), outcome: String.t(), ended: Date.t() | nil, dir: String.t()}
  @type survey :: %{
          folders: [folder()],
          prs: non_neg_integer(),
          kept: non_neg_integer(),
          stray: non_neg_integer(),
          kb: non_neg_integer() | nil,
          problem: String.t() | nil
        }
  @type cleaned :: %{
          folders: non_neg_integer(),
          prs: non_neg_integer(),
          kept: non_neg_integer(),
          failed: non_neg_integer()
        }

  @doc "The retention choices, in days."
  def choices, do: @choices

  @doc "How long this project keeps an ended ticket's folder."
  @spec days(Superagent.t()) :: pos_integer() | :never
  def days(%Superagent{} = superagent) do
    case Settings.get(key(superagent)) do
      "never" -> :never
      value when is_binary(value) -> Enum.find(@choices, @default, &(to_string(&1) == value))
      _ -> @default
    end
  end

  @spec put_days(Superagent.t(), pos_integer() | :never) :: :ok | {:error, :invalid}
  def put_days(%Superagent{} = superagent, days) when days == :never or days in @choices,
    do: Settings.put(key(superagent), to_string(days))

  def put_days(%Superagent{}, _days), do: {:error, :invalid}

  defp key(%Superagent{profile: profile}), do: "agent_folder_days:#{profile}"

  @doc """
  What the ended tickets of this agent hold now. It changes nothing; it reads
  the agent's database, each folder's git status and, when a ticket ended
  without a merge, the repository's open pull requests as the agent.
  """
  @spec survey(Superagent.t()) :: {:ok, survey()} | {:error, term()}
  def survey(%Superagent{} = superagent) do
    with {:ok, %{rows: rows, notes: notes, code: code}} <- run(superagent, []) do
      folders =
        for ["remove", name, outcome, day, dir | _rest] <- rows,
            do: %{name: name, outcome: outcome, ended: date(day), dir: dir}

      {:ok,
       %{
         folders: folders,
         prs: count(rows, "close"),
         kept: count(rows, "skip"),
         stray: stray(notes),
         kb: weight(folders),
         problem: if(code != 0, do: List.last(notes) || "exit #{code}")
       }}
    end
  end

  @doc "The folders of a survey that ended at least `days` days ago."
  @spec past([folder()], pos_integer() | :never, Date.t()) :: [folder()]
  def past(_folders, :never, _today), do: []

  def past(folders, days, today),
    do: Enum.filter(folders, &(&1.ended && Date.diff(today, &1.ended) >= days))

  @doc """
  Removes. `:all` is every ended folder and the orphan pull requests;
  `{:older_than, days}` is folders only. An effect: called only by
  `AgentBoard.Actions`.
  """
  @spec clean(Superagent.t(), :all | {:older_than, pos_integer()}) ::
          {:ok, cleaned()} | {:error, term()}
  def clean(%Superagent{} = superagent, scope) do
    with {:ok, %{rows: rows, notes: notes, code: code}} <- run(superagent, apply_args(scope)) do
      cleaned = %{
        folders: count(rows, "removed"),
        prs: count(rows, "closed"),
        kept: count(rows, "skip"),
        failed: count(rows, "FAILED")
      }

      if code == 0,
        do: {:ok, cleaned},
        else: {:error, {:partial, cleaned, List.last(notes) || failure(rows)}}
    end
  end

  defp apply_args(:all), do: ["--apply"]

  defp apply_args({:older_than, days}) when is_integer(days) and days > 0,
    do: ["--apply" | older_than(days)]

  defp older_than(days), do: ["--no-prs", "--older-than", Integer.to_string(days)]

  @doc """
  The daily retention: for each project that keeps folders for a number of
  days, removes the older ones. The action runs only when the dry run finds
  one, so a recorded decision is always a removal.
  """
  @spec sweep() :: :ok
  def sweep do
    for superagent <- Superagents.list(), days = days(superagent), days != :never do
      case run(superagent, older_than(days)) do
        {:ok, %{rows: rows}} ->
          remove_past(superagent, days, count(rows, "remove"))

        # An agent that was never started has no database: nothing to keep.
        {:error, reason} ->
          Logger.info("folder retention skipped #{superagent.profile}: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp remove_past(_superagent, _days, 0), do: :ok

  defp remove_past(superagent, days, _past) do
    Actions.run(
      :sweep_agent_folders,
      %{superagent: superagent, days: days},
      Actions.system("folder_retention")
    )
  end

  # shortcut: no timeout on the script, a hung git holds only the task that
  # called it; add one if a survey is ever seen stuck.
  defp run(%Superagent{state_dir: dir} = superagent, args) when is_binary(dir) and dir != "" do
    script = Application.get_env(:agent_board, :agent_cleanup_script, @script)

    if File.exists?(script) do
      # Each agent's own folders, whatever the board's environment says.
      env = [
        {"SUPERAGENT_STATE_DIR", dir},
        {"SUPERAGENT_WORK_DIR", Path.join(dir, "work")},
        {"DSH_SUPERAGENT_PROFILE", superagent.profile}
      ]

      {output, code} = System.cmd("sh", [script | args], env: env, stderr_to_stdout: true)
      {rows, notes} = output |> String.split("\n", trim: true) |> Enum.split_with(&row?/1)

      if rows == [] and code != 0,
        do: {:error, List.last(notes) || "exit #{code}"},
        else: {:ok, %{rows: Enum.map(rows, &fields/1), notes: notes, code: code}}
    else
      {:error, :unavailable}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp run(%Superagent{}, _args), do: {:error, :unavailable}

  # The script's own lines start with what it did; anything else is stderr.
  @verbs ~w(remove removed close closed skip prune pruned FAILED dry-run: done:)
  defp row?(line), do: line |> String.split(" ", parts: 2) |> hd() |> Kernel.in(@verbs)

  defp fields(line), do: String.split(line, ~r/ {2,}/)

  defp count(rows, verb), do: Enum.count(rows, &(hd(&1) == verb))

  defp failure(rows) do
    case Enum.find(rows, &(hd(&1) == "FAILED")) do
      nil -> nil
      row -> Enum.join(tl(row), " ")
    end
  end

  # "note: left alone, no ticket in <db>: a b c": folders no ticket names.
  defp stray(notes) do
    case Enum.find(notes, &String.starts_with?(&1, "note: left alone")) do
      nil -> 0
      note -> note |> String.split(":") |> List.last() |> String.split() |> length()
    end
  end

  defp date(day) do
    case Date.from_iso8601(day) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  # Kilobytes on disk, or nil when du did not answer for every folder.
  defp weight([]), do: 0

  defp weight(folders) do
    case System.cmd("du", ["-sk" | Enum.map(folders, & &1.dir)], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reduce(0, fn line, sum ->
          {kb, _rest} = Integer.parse(line)
          sum + kb
        end)

      _ ->
        nil
    end
  rescue
    _exception -> nil
  end
end
