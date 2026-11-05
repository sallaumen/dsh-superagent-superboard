defmodule AgentBoardWeb.BoardComponents.VoiceCommand do
  @moduledoc "Editable voice transcript and grounded command feedback."
  use Phoenix.Component

  alias AgentBoardWeb.BoardComponents.DataAge

  attr :draft, :string, required: true
  attr :result, :map, default: nil

  def draft(assigns) do
    ~H"""
    <section class="voice-command-draft" aria-labelledby="voice-command-heading">
      <p id="voice-command-heading" class="voice-command-intro">
        Review what the board heard. Recording does not send a message or change a task.
      </p>
      <form id="voice-command-form" phx-change="voice_draft_changed">
        <label for="voice-command-text">Command</label>
        <textarea
          id="voice-command-text"
          name="text"
          rows="4"
          maxlength="2000"
          placeholder="Type a command or press Space twice on the board to record one"
        >{@draft}</textarea>
      </form>
      <div :if={@result} class="voice-command-result" data-kind={@result.kind} role="status">
        <p>{@result.text}</p>
        <DataAge.stamp
          :if={@result.as_of}
          id="voice-result-age"
          at={@result.as_of}
          label={Map.get(@result, :source, "Record updated")}
        />
        <a
          :if={Map.get(@result, :url)}
          href={@result.url}
          target="_blank"
          rel="noopener noreferrer"
        >Open pull request on GitHub in a new tab</a>
      </div>
      <p class="voice-command-hint">Close this panel to return to the board.</p>
    </section>
    """
  end
end
