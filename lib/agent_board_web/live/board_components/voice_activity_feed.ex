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

  alias AgentBoard.ElevenLabs.Usage

  attr :events, :list, required: true

  def feed(assigns) do
    assigns = assign(assigns, usage: Usage.today(), cap: Usage.cap())

    ~H"""
    <details id="voice-activity" class="voice-activity" open={has_problem?(@events)}>
      <summary>
        <span class="voice-activity-title">Bastidores da voz</span>
        <span class="voice-activity-summary">
          {summary(@events)}<span id="voice-usage-today"> · {usage(@usage, @cap)}</span>
        </span>
      </summary>
      <p :if={@events == []} class="voice-activity-empty">
        Nada ainda. Cada etapa de uma fala aparece aqui na hora: transcrição, modelo, voz, re-tentativas e erros.
      </p>
      <ol
        :if={@events != []}
        id="voice-activity-events"
        class="voice-activity-events"
        aria-live="polite"
      >
        <li :for={event <- @events} class="voice-activity-event" data-status={event.status}>
          <time datetime={DateTime.to_iso8601(event.at)}>{clock(event.at)}</time>
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

  defp summary([]), do: "sem eventos"

  defp summary(events) do
    errors = Enum.count(events, &(&1.status == :error))
    retries = Enum.count(events, &(&1.status == :retry))

    [
      "#{length(events)} eventos",
      errors > 0 && "#{errors} #{if errors == 1, do: "erro", else: "erros"}",
      retries > 0 && "#{retries} #{if retries == 1, do: "re-tentativa", else: "re-tentativas"}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  @doc """
  Today's ElevenLabs usage in words: "hoje: 3.420 de 20.000 caracteres ·
  1,2 min transcritos · 18 do cache". The minutes and the cache hits show
  only when there are some; the cap only when there is one.
  """
  @spec usage(Usage.day(), non_neg_integer()) :: String.t()
  def usage(usage, cap) do
    chars = Usage.number(usage.tts_characters)

    [
      if(cap > 0,
        do: "hoje: #{chars} de #{Usage.number(cap)} caracteres",
        else: "hoje: #{chars} caracteres"
      ),
      usage.stt_seconds > 0 && "#{minutes(usage.stt_seconds)} min transcritos",
      usage.cache_hits > 0 && "#{usage.cache_hits} do cache"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp minutes(seconds),
    do: :erlang.float_to_binary(seconds / 60, decimals: 1) |> String.replace(".", ",")

  # The board shows times in UTC like the header's sync line.
  defp clock(at), do: Calendar.strftime(at, "%H:%M:%S")

  defp ms(ms) when ms < 1000, do: "#{ms} ms"

  defp ms(ms),
    do:
      :erlang.float_to_binary(ms / 1000, decimals: 1)
      |> String.replace(".", ",")
      |> Kernel.<>(" s")

  defp stage(:turn), do: "fala"
  defp stage(:transcribe), do: "transcrição"
  defp stage(:model), do: "modelo"
  defp stage(:action), do: "ação"
  defp stage(:tts), do: "voz"
  defp stage(:voices), do: "vozes"
  defp stage(:browser), do: "navegador"
  defp stage(:ui), do: "tela"
  defp stage(other), do: to_string(other)
end
