defmodule AgentBoardWeb.BoardComponents.VoiceActivityFeed do
  @moduledoc """
  The voice pipeline as it happens: each stage of a turn with its time,
  every retry and every failure (server or browser), newest first. Fed live
  by `AgentBoard.Voice.Activity` over PubSub; the same lines are in the log.
  """
  use Phoenix.Component

  attr :events, :list, required: true

  def feed(assigns) do
    ~H"""
    <details id="voice-activity" class="voice-activity" open={has_problem?(@events)}>
      <summary>
        <span class="voice-activity-title">Bastidores da voz</span>
        <span class="voice-activity-summary">{summary(@events)}</span>
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
