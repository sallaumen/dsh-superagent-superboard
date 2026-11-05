defmodule AgentBoardWeb.BoardComponents.CreateTask do
  @moduledoc "The board's createtask region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <footer id={@id} class="border-t border-base-content/10 p-5">
      <form id="create-task" phx-submit="create" class="flex flex-wrap gap-2">
        <input
          name="title"
          id="task-title"
          aria-label="Task title"
          placeholder="New task: what should the agent build?"
          class="flex-1 border border-base-content/10 bg-base-200 px-3 py-2 text-sm"
          required
        />
        <button
          class="bg-primary px-4 py-2 text-sm font-bold text-primary-content hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          phx-disable-with="Creating…"
        >Create issue</button>
        <textarea
          name="body"
          aria-label="Task details"
          placeholder="Details (optional). The agent is mentioned automatically."
          class="w-full border border-base-content/10 bg-base-200 px-3 py-2 text-sm"
        ></textarea>
      </form>
    </footer>
    """
  end
end
