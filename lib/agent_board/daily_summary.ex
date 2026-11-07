defmodule AgentBoard.DailySummary do
  @moduledoc """
  The summary of the day on a wall clock (`docs/research/alfred.md`, F1.6).

  `Oban.Cron` only inserts a job when its expression matches the minute it
  evaluates, so an 08:00 missed while the Mac slept is never recovered. This
  routine asks a different question on every tick: **has today's summary
  gone out, now that it is past the configured hour?** If not, it is
  generated once and recorded as one row per local day (`daily_summaries`,
  unique `local_date`): a second tick, a restart or a second board on the
  same database finds the row and does nothing.

  The day is the owner's: the Mac's local clock (`:calendar`), or the
  `:utc_offset` option in minutes east of UTC (tests). The hour and the
  switch are board-wide settings (`daily_summary_at`, default 08:00;
  `daily_summary_enabled`, `"false"` switches it off), edited in
  Configurações.

  The content is collected once by `AgentBoard.DailySummary.Facts` and
  stored in the row; the board renders that record, and the voice speaks it
  through `AgentBoard.Voice.Phrases` by template, once (`claim_spoken/1`).
  Every change is `{:daily_summary, :generated | :dismissed, id}` on
  `topic/0`.
  """
  use GenServer

  import Ecto.Query, warn: false
  require Logger

  alias AgentBoard.DailySummary.{Entry, Facts}
  alias AgentBoard.{Repo, Settings}

  @topic "daily_summary"
  @enabled_key "daily_summary_enabled"
  @at_key "daily_summary_at"
  @default_at ~T[08:00:00]
  # The first summary looks back one day; after a long sleep, at most a week.
  @first_window 24 * 3600
  @max_window 7 * 24 * 3600

  @type outcome :: {:generated, Entry.t()} | :exists | :not_due | :disabled

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %{
      interval: Keyword.get(opts, :interval, interval()),
      tick_opts: Keyword.get(opts, :tick_opts, [])
    }

    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule(state)

    try do
      tick(state.tick_opts)
    rescue
      # The database can fail mid-tick; the schedule survives and the next
      # tick asks again.
      exception -> Logger.warning("daily_summary tick failed: #{Exception.message(exception)}")
    end

    {:noreply, state}
  end

  defp schedule(%{interval: :manual}), do: :ok
  defp schedule(%{interval: ms}), do: Process.send_after(self(), :tick, ms)
  defp interval, do: Application.get_env(:agent_board, :daily_summary_interval, 60_000)

  @doc "The PubSub topic of generated and dismissed summaries."
  def topic, do: @topic

  @doc "Subscribes the caller to `{:daily_summary, event, id}`."
  def subscribe, do: Phoenix.PubSub.subscribe(AgentBoard.PubSub, @topic)

  @doc """
  One pass of the wall clock: generates today's summary when it is past the
  configured hour and today has no row yet.

  Options: `:now` (UTC), `:utc_offset` (minutes east of UTC; the Mac's zone
  when absent) and `:spend` (the executor reader, see `Facts.collect/3`).
  """
  @spec tick(keyword()) :: outcome()
  def tick(opts \\ []) do
    now = opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.truncate(:second)
    settings = settings()
    local = local_now(now, opts)
    date = NaiveDateTime.to_date(local)

    cond do
      not settings.enabled -> :disabled
      Time.compare(NaiveDateTime.to_time(local), settings.at) == :lt -> :not_due
      exists?(date) -> :exists
      true -> generate(date, now, opts)
    end
  end

  defp exists?(date), do: Repo.exists?(from e in Entry, where: e.local_date == ^date)

  # The unique local date is the claim: of two ticks that both found no row,
  # one inserts and the other conflicts and says nothing.
  defp generate(date, now, opts) do
    since = window_start(now)

    attrs = %{
      local_date: date,
      generated_at: now,
      window_start: since,
      window_end: now,
      content: Facts.collect(since, now, opts)
    }

    case %Entry{}
         |> Entry.changeset(attrs)
         |> Repo.insert(on_conflict: :nothing, conflict_target: :local_date) do
      {:ok, %Entry{id: id} = entry} when not is_nil(id) ->
        Logger.info(
          "daily_summary date=#{date} outcome=generated since=#{DateTime.to_iso8601(since)}"
        )

        broadcast(:generated, id)
        {:generated, entry}

      {:ok, _conflict} ->
        :exists

      {:error, changeset} ->
        Logger.warning("daily_summary date=#{date} outcome=invalid #{inspect(changeset.errors)}")
        :exists
    end
  end

  # Everything since the previous summary, so a day missed while the Mac
  # slept is not lost; the first one looks back a day, and nothing looks
  # back more than a week.
  defp window_start(now) do
    floor = DateTime.add(now, -@max_window, :second)

    previous =
      Repo.one(
        from e in Entry,
          where: e.window_end <= ^now,
          order_by: [desc: e.window_end],
          limit: 1,
          select: e.window_end
      )

    cond do
      is_nil(previous) -> DateTime.add(now, -@first_window, :second)
      DateTime.compare(previous, floor) == :lt -> floor
      true -> previous
    end
  end

  @doc """
  The owner's wall clock for a UTC instant: `:utc_offset` minutes east of
  UTC when given, else the Mac's own zone.
  """
  @spec local_now(DateTime.t(), keyword()) :: NaiveDateTime.t()
  def local_now(%DateTime{} = now, opts \\ []) do
    case Keyword.get(opts, :utc_offset) do
      offset when is_integer(offset) ->
        now |> DateTime.add(offset * 60, :second) |> DateTime.to_naive()

      nil ->
        now
        |> DateTime.truncate(:second)
        |> DateTime.to_naive()
        |> NaiveDateTime.to_erl()
        |> :calendar.universal_time_to_local_time()
        |> NaiveDateTime.from_erl!()
    end
  end

  # ---- settings --------------------------------------------------------------

  @doc "The switch and the hour: on at 08:00 unless saved otherwise."
  @spec settings() :: %{enabled: boolean(), at: Time.t()}
  def settings do
    %{
      enabled: Settings.get(@enabled_key) != "false",
      at: parse_at(Settings.get(@at_key)) || @default_at
    }
  end

  @doc """
  Saves the settings form: `"enabled"` (`"true"`/`"false"`) and `"at"`
  (`HH:MM`). A malformed hour saves nothing and answers `:invalid_time`.
  """
  @spec put_settings(map()) :: :ok | {:error, :invalid_time | :invalid}
  def put_settings(params) do
    with :ok <- put_at(params["at"]) do
      put_enabled(params["enabled"])
    end
  end

  defp put_at(nil), do: :ok

  defp put_at(value) do
    case parse_at(value) do
      nil -> {:error, :invalid_time}
      time -> Settings.put(@at_key, format_at(time))
    end
  end

  defp put_enabled(nil), do: :ok
  defp put_enabled(value) when value in ["true", "false"], do: Settings.put(@enabled_key, value)
  defp put_enabled(_value), do: {:error, :invalid}

  @doc "`HH:MM` for an hour, as the settings form shows it."
  def format_at(%Time{hour: h, minute: m}),
    do: "#{String.pad_leading("#{h}", 2, "0")}:#{String.pad_leading("#{m}", 2, "0")}"

  defp parse_at(value) when is_binary(value) do
    with [_, h, m] <- Regex.run(~r/\A(\d{2}):(\d{2})(?::\d{2})?\z/, String.trim(value)),
         {:ok, time} <- Time.new(String.to_integer(h), String.to_integer(m), 0) do
      time
    else
      _ -> nil
    end
  end

  defp parse_at(_value), do: nil

  # ---- the board's side -------------------------------------------------------

  @doc "Today's summary (the owner's day) unless it was dismissed; nil otherwise."
  @spec visible(keyword()) :: Entry.t() | nil
  def visible(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    date = now |> local_now(opts) |> NaiveDateTime.to_date()
    Repo.one(from e in Entry, where: e.local_date == ^date and is_nil(e.dismissed_at))
  end

  @doc "Hides a summary on every board."
  @spec dismiss(integer()) :: :ok
  def dismiss(id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    query = from e in Entry, where: e.id == ^id and is_nil(e.dismissed_at)

    case Repo.update_all(query, set: [dismissed_at: now]) do
      {1, _} -> broadcast(:dismissed, id)
      _none -> :ok
    end
  end

  @doc """
  Claims the right to speak a summary: true for the first caller only, so
  two open boards (or a reconnect) never say it twice.
  """
  @spec claim_spoken(integer()) :: boolean()
  def claim_spoken(id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    query = from e in Entry, where: e.id == ^id and is_nil(e.spoken_at)
    match?({1, _}, Repo.update_all(query, set: [spoken_at: now]))
  end

  defp broadcast(event, id) do
    Phoenix.PubSub.broadcast(AgentBoard.PubSub, @topic, {:daily_summary, event, id})
  end
end
