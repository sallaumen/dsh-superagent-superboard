defmodule AgentBoardWeb.BoardComponents.StatusMark do
  @moduledoc """
  A state is a shape plus a word.

  The color confirms the meaning; it never carries it alone. `agent` and
  `halt` have similar lightness, so a screen reader and a person both get the
  glyph and the word.
  """
  use AgentBoardWeb, :html

  @statuses %{
    run: %{glyph: "run", word: "Rodando", tone: "run"},
    review: %{glyph: "you", word: "Para revisar", tone: "you"},
    question: %{glyph: "you", word: "Pergunta", tone: "you"},
    blocked: %{glyph: "halt", word: "Bloqueado", tone: "halt"},
    cifail: %{glyph: "halt", word: "CI falhou", tone: "halt"},
    stalled: %{glyph: "halt", word: "Sem sinal", tone: "halt"},
    queue: %{glyph: "queue", word: "Na fila", tone: "queue"},
    done: %{glyph: "done", word: "Mesclado", tone: "done"},
    stale: %{glyph: "stale", word: "Dado antigo", tone: "stale"},
    unknown: %{glyph: "unknown", word: "Desconhecido", tone: "queue"}
  }

  attr :kind, :atom, required: true
  attr :word, :string, default: nil
  attr :live, :boolean, default: false

  def status_mark(assigns) do
    assigns = assign(assigns, :status, Map.get(@statuses, assigns.kind, @statuses.unknown))

    ~H"""
    <span class={"ab-status ab-status--#{@status.tone}"}>
      <.glyph kind={@kind} live={@live} />
      {@word || @status.word}
    </span>
    """
  end

  attr :kind, :atom, required: true
  attr :live, :boolean, default: false

  def glyph(assigns) do
    status = Map.get(@statuses, assigns.kind, @statuses.unknown)
    assigns = assign(assigns, :glyph, status.glyph)

    ~H"""
    <i
      class={"ab-g ab-g--#{@glyph}" <> if(@live, do: " is-live", else: "")}
      aria-hidden="true"
    ></i>
    """
  end
end
