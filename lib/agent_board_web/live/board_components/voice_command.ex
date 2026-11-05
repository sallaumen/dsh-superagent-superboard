defmodule AgentBoardWeb.BoardComponents.VoiceCommand do
  @moduledoc "Editable voice transcript and grounded command feedback."
  use Phoenix.Component

  alias AgentBoardWeb.BoardComponents.DataAge
  alias AgentBoardWeb.BoardComponents.VoiceActionConfirmation

  attr :draft, :string, required: true
  attr :result, :map, default: nil
  attr :action, :map, default: nil

  def draft(assigns) do
    ~H"""
    <section class="voice-command-draft" aria-labelledby="voice-command-heading">
      <p id="voice-command-heading" class="voice-command-intro">
        Review what the board heard. Recording does not send a message or change a task.
      </p>
      <form id="voice-command-form" phx-change="voice_draft_changed" phx-submit="voice_command">
        <label for="voice-command-text">Command</label>
        <textarea
          id="voice-command-text"
          name="text"
          rows="4"
          maxlength="2000"
          required
          placeholder="Type a command or press Space twice on the board to record one"
        >{@draft}</textarea>
        <div :if={is_nil(@action)} class="voice-command-actions">
          <button type="submit" class="voice-command-run" phx-disable-with="Checking…">
            Check command
          </button>
          <button
            :if={@result && @result.kind == :ask}
            type="button"
            phx-click="voice_ask"
            phx-value-question={@result.question}
            class="voice-command-run"
            phx-disable-with="Sending…"
          >
            Ask the agent
          </button>
        </div>
      </form>
      <VoiceActionConfirmation.review :if={@action} intent={@action} />
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
