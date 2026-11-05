defmodule AgentBoardWeb.BoardComponents.CreateTask do
  @moduledoc "The task creation form. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="create-task-panel">
      <p class="create-task-note">Open an issue in the selected repository and mention the agent.</p>
      <form id="create-task" phx-submit="create" class="create-task-form">
        <label for="task-title">Task title</label>
        <input
          name="title"
          id="task-title"
          placeholder="What should the agent build?"
          required
        />
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
