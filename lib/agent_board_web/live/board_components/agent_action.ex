defmodule AgentBoardWeb.BoardComponents.AgentAction do
  @moduledoc """
  One action on the agent, in place: a button, a confirmation that names
  what will happen, a loading state and the result. Nothing runs on the
  first click.

    * `:retry` - "Tentar de novo" / "Tentar agora" (`AgentControl.retry/2`)
    * `:restart` - "Religar o agente" (`AgentControl.start_agent/1`)
    * `:stop` - "Parar": only the confirmation lives here; the confirmed
      click is BoardLive's `act` event, the same one the button sent before.

  The result stays until the next action, so a board reload (every poll)
  does not erase it.
  """
  use AgentBoardWeb, :live_component

  alias AgentBoard.AgentControl
  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket), do: {:ok, assign(socket, step: :idle, result: nil, refocus: false)}

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:tone, fn -> :quiet end)
     |> assign_new(:ticket_id, fn -> nil end)
     |> assign_new(:task_id, fn -> nil end)
     |> assign_new(:repository_id, fn -> nil end)
     |> assign_new(:number, fn -> nil end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ab-act" data-step={@step}>
      <button
        :if={@step in [:idle, :done]}
        id={"#{@id}-trigger"}
        type="button"
        class={["ab-btn ab-btn--sm", tone(@tone)]}
        phx-click="ask"
        phx-target={@myself}
        phx-mounted={@refocus && JS.focus()}
      >
        {@label}
      </button>

      <div :if={@step == :confirm} class="ab-act__confirm" role="group" aria-labelledby={"#{@id}-q"}>
        <p id={"#{@id}-q"} class="ab-act__question">{@question}</p>
        <div class="ab-act__buttons">
          <button
            :if={@mode == :stop}
            id={"#{@id}-confirm"}
            type="button"
            class={["ab-btn ab-btn--sm", tone(@tone)]}
            phx-click="act"
            phx-value-id={@task_id}
            phx-value-action="stop"
            phx-disable-with={@busy_label}
            phx-mounted={JS.focus()}
          >
            {@confirm_label}
          </button>
          <button
            :if={@mode != :stop}
            id={"#{@id}-confirm"}
            type="button"
            class={["ab-btn ab-btn--sm", tone(@tone)]}
            phx-click="go"
            phx-target={@myself}
            phx-mounted={JS.focus()}
          >
            {@confirm_label}
          </button>
          <button
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="cancel"
            phx-target={@myself}
          >
            Cancelar
          </button>
        </div>
      </div>

      <p :if={@step == :busy} class="ab-act__busy" role="status">
        <span class="ab-act__spin" aria-hidden="true"></span>{@busy_label}
      </p>

      <p
        :if={@result && @step == :done}
        class={["ab-act__result", @result.tone == :error && "is-error"]}
        role="status"
      >
        {@result.text}
      </p>
    </div>
    """
  end

  @impl true
  def handle_event("ask", _params, socket),
    do: {:noreply, assign(socket, step: :confirm, result: nil, refocus: false)}

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, step: :idle, refocus: true)}

  # Only a confirmation starts the work, and only once.
  def handle_event("go", _params, %{assigns: %{step: :confirm}} = socket) do
    action = action(socket.assigns)
    {:noreply, socket |> assign(step: :busy) |> start_async(:run, action)}
  end

  def handle_event("go", _params, socket), do: {:noreply, socket}

  # A restart that worked removes the item this button lives in (the next
  # reload no longer finds the orchestrator down), and a component's flash
  # never reaches the page: the LiveView says the result and reloads.
  @impl true
  def handle_async(:run, {:ok, {:ok, text}}, %{assigns: %{mode: :restart}} = socket) do
    send(self(), {:agent_restarted, text})
    {:noreply, assign(socket, step: :done, result: %{tone: :ok, text: text})}
  end

  def handle_async(:run, {:ok, {:ok, text}}, socket),
    do: {:noreply, assign(socket, step: :done, result: %{tone: :ok, text: text})}

  def handle_async(:run, {:ok, {:error, text}}, socket),
    do: {:noreply, assign(socket, step: :done, result: %{tone: :error, text: text})}

  def handle_async(:run, {:exit, reason}, socket) do
    text = "A ação não terminou: #{inspect(reason)}"
    {:noreply, assign(socket, step: :done, result: %{tone: :error, text: text})}
  end

  defp action(%{mode: :retry} = assigns) do
    opts = [repository_id: assigns.repository_id, number: assigns.number]
    ticket_id = assigns.ticket_id
    fn -> AgentControl.retry(ticket_id, opts) end
  end

  defp action(%{mode: :restart}), do: fn -> AgentControl.start_agent() end

  defp tone(:halt), do: "ab-btn--halt"
  defp tone(:primary), do: "ab-btn--primary"
  defp tone(_quiet), do: "ab-btn--quiet"
end
