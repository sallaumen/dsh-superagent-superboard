defmodule AgentBoardWeb.BoardComponents.CreateTask do
  @moduledoc "The task creation form. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  attr :voice_configured, :boolean, default: false

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="create-task-panel">
      <p class="create-task-note">Open an issue in the selected repository and mention the agent.</p>
      <form id="create-task" phx-submit="create" class="create-task-form">
        <label for="task-title">Task title</label>
        <div class="create-task-title-row">
          <input
            name="title"
            id="task-title"
            placeholder="What should the agent build?"
            required
          />
          <button
            :if={@voice_configured}
            id="record-task-title"
            type="button"
            phx-hook="VoiceRecorder"
            data-target="#task-title"
            data-max-seconds="20"
            aria-label="Record task title"
            class="create-task-voice"
          >
            <.icon name="hero-microphone" class="size-4 shrink-0" />
            <span data-voice-button-label>Record title</span>
          </button>
          <button
            :if={not @voice_configured}
            id="dictate-task-title"
            type="button"
            phx-click="dictate"
            aria-label="Dictate task title with browser speech"
            class="create-task-voice"
          >
            <.icon name="hero-microphone" class="size-4 shrink-0" /> Dictate title
          </button>
        </div>
        <label for="task-body">Details <span>(optional)</span></label>
        <textarea
          name="body"
          id="task-body"
          placeholder="Context, requirements, and links"
        ></textarea>
        <button class="create-task-submit" phx-disable-with="Creating…">Create issue</button>
      </form>
    </section>
    """
  end
end
