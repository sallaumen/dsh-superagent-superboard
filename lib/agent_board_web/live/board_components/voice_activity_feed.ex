defmodule AgentBoardWeb.BoardComponents.VoiceActivityFeed do
  @moduledoc """
  The voice pipeline as it happens: each stage of a turn with its time,
  every retry and every failure (server or browser), newest first. Fed live
  by `AgentBoard.Voice.Activity` over PubSub; the same lines are in the log.
  The summary also says what ElevenLabs cost today
  (`AgentBoard.ElevenLabs.Usage`), read again each time the feed changes:
  one primary-key query, and every paid call or cache hit is an event.
  """
  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.ElevenLabs.{Account, Usage}

  attr :events, :list, required: true
  attr :tz_offset, :integer, default: 0

  def feed(assigns) do
    now = DateTime.utc_now()

    assigns =
      assign(assigns,
        usage: Usage.today(),
        cap: Usage.cap(),
        account: account(Account.snapshot(), now, assigns.tz_offset)
      )

    ~H"""
    <details id="voice-activity" class="voice-activity" open={has_problem?(@events)}>
      <summary>
        <span class="voice-activity-title">{gettext("Voice activity")}</span>
        <span class="voice-activity-summary">
          {summary(@events)}<span id="voice-usage-today"> · {usage(@usage, @cap)}</span><span
            :if={@account}
            id="voice-account"
          > · {@account}</span>
        </span>
      </summary>
      <p :if={@events == []} class="voice-activity-empty">
        {gettext(
          "Nothing yet. Every step of a speech appears here in real time: transcription, model, voice, retries, and errors."
        )}
      </p>
      <ol
        :if={@events != []}
        id="voice-activity-events"
        class="voice-activity-events"
        aria-live="polite"
      >
        <li :for={event <- @events} class="voice-activity-event" data-status={event.status}>
          <time datetime={DateTime.to_iso8601(event.at)}>{clock(event.at, @tz_offset)}</time>
          <span class="voice-activity-stage">{stage(event.stage)}</span>
          <span class="voice-activity-detail">
            {event.detail}<span :if={event.ms} class="voice-activity-ms"> · {ms(event.ms)}</span>
          </span>
        </li>
      </ol>
    </details>
    """
  end

  defp has_problem?(events), do: Enum.any?(Enum.take(events, 5), &(&1.status in [:error, :retry]))

  defp summary([]), do: gettext("no events")

  defp summary(events) do
    errors = Enum.count(events, &(&1.status == :error))
    retries = Enum.count(events, &(&1.status == :retry))

    [
      ngettext("%{count} event", "%{count} events", length(events)),
      errors > 0 && ngettext("%{count} error", "%{count} errors", errors),
      retries > 0 && ngettext("%{count} retry", "%{count} retries", retries)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  @doc """
  Today's ElevenLabs usage in words, including characters, transcription
  minutes, and cache hits. The minutes and the cache hits show
  only when there are some; the cap only when there is one.
  """
  @spec usage(Usage.day(), non_neg_integer()) :: String.t()
  def usage(usage, cap) do
    chars = number(usage.tts_characters)

    [
      if(cap > 0,
        do: gettext("today: %{count} of %{cap} characters", count: chars, cap: number(cap)),
        else: gettext("today: %{count} characters", count: chars)
      ),
      usage.stt_seconds > 0 &&
        gettext("%{minutes} min transcribed", minutes: minutes(usage.stt_seconds)),
      usage.cache_hits > 0 && gettext("%{count} from cache", count: usage.cache_hits)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  @doc """
  The ElevenLabs plan in words, from `Account.snapshot/0`: what this period
  used and when it renews, or that the computer voice speaks because it is
  spent. Nil before the account was ever read.
  """
  @spec account(Account.t(), DateTime.t(), integer()) :: String.t() | nil
  def account(%{subscription: %{} = sub} = state, now, offset) do
    cond do
      Account.plan_spent?(state, now) ->
        gettext("plan spent until %{date}: the computer voice speaks",
          date: day(sub.resets_at, offset)
        )

      refused?(state, now) ->
        refused_text(state, offset)

      sub.resets_at ->
        gettext("plan: %{used} of %{limit} characters this period, renews %{date}",
          used: number(sub.used),
          limit: number(sub.limit),
          date: day(sub.resets_at, offset)
        )

      true ->
        gettext("plan: %{used} of %{limit} characters this period",
          used: number(sub.used),
          limit: number(sub.limit)
        )
    end
  end

  def account(state, now, offset), do: if(refused?(state, now), do: refused_text(state, offset))

  defp refused?(%{refused_until: %DateTime{} = until}, now),
    do: DateTime.compare(now, until) == :lt

  defp refused?(_state, _now), do: false

  defp refused_text(state, offset),
    do:
      gettext("a speech was refused for credits: the computer voice speaks until %{time}",
        time: AgentBoardWeb.Time.local_time(state.refused_until, offset)
      )

  defp day(nil, _offset), do: "—"

  defp day(at, offset) do
    date = AgentBoardWeb.Time.local_date(at, offset)
    "#{date.day} #{AgentBoardWeb.Time.month(date)}"
  end

  defp minutes(seconds),
    do: :erlang.float_to_binary(seconds / 60, decimals: 1) |> decimal()

  defp number(value) do
    formatted = Usage.number(value)
    if portuguese?(), do: formatted, else: String.replace(formatted, ".", ",")
  end

  defp decimal(value), do: if(portuguese?(), do: String.replace(value, ".", ","), else: value)
  defp portuguese?, do: Gettext.get_locale(AgentBoardWeb.Gettext) == "pt_BR"

  # The board shows times in UTC like the header's sync line.
  defp clock(at, offset),
    do: at |> AgentBoardWeb.Time.local(offset) |> Calendar.strftime("%H:%M:%S")

  defp ms(ms) when ms < 1000, do: "#{ms} ms"

  defp ms(ms),
    do:
      :erlang.float_to_binary(ms / 1000, decimals: 1)
      |> decimal()
      |> Kernel.<>(" s")

  defp stage(:turn), do: gettext("speech")
  defp stage(:transcribe), do: gettext("transcription")
  defp stage(:model), do: gettext("model")
  defp stage(:action), do: gettext("Action")
  defp stage(:tts), do: gettext("voice")
  defp stage(:voices), do: gettext("voices")
  defp stage(:browser), do: gettext("browser")
  defp stage(:ui), do: gettext("screen")
  defp stage(other), do: to_string(other)
end
