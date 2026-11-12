defmodule AgentBoardWeb.BoardComponents.AgentAction do
  @moduledoc """
  One red action, in place: a button, a confirmation that says the
  action's sentence (`AgentBoard.Actions.phrase/3`, the same the voice
  says), a loading state and the result. Nothing runs on the first click;
  the confirmation passes that sentence to the gate, and Cancelar records
  the refusal.

    * `:retry` - "Tentar de novo" / "Tentar agora" (`:retry_ticket`)
    * `:restart` - "Religar o agente": the repository's own superagent
      (`:start_superagent`) when it has one, else the primary (`:start_agent`)
    * `:dispatch` - "Despachar" para o Claude Code ou o Codex (`:dispatch_task`)
    * `:stop` - "Parar" (`:stop_task`): only the confirmation lives here;
      the confirmed click is BoardLive's `act` event, carrying the sentence.
    * `:share_private` - "Avisar o agente na issue" (`:share_private_context`)
    * `:grant_agent_access`, `:revoke_agent_access` - who may use a project's
      agent; the row leaves on success, so BoardLive says the result.
    * `:clean_agent_leftovers` - "Remover tudo agora": the folders and orphan
      pull requests of a project's ended tickets.
    * `:adopt_superagent` - "Adicionar ao board": an agent installed on this
      machine outside the board; its row leaves on success, so BoardLive says
      the result.

  `notify={{module, id}}` hands the result to a live component
  (`send_update(module, id: id, done: mode, text: text)`), for a caller whose
  own numbers the action just changed: it may stop rendering this button, so
  it is the one that shows the text.

  The result stays until the next action, so a board reload (every poll)
  does not erase it.
  """
  use AgentBoardWeb, :live_component

  alias AgentBoard.{Actions, Board, Superagents}
  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.Superagents.Superagent
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
     |> assign_new(:number, fn -> nil end)
     |> assign_new(:task, fn -> nil end)
     |> assign_new(:executor, fn -> nil end)
     |> assign_new(:ceiling_usd, fn -> nil end)
     |> assign_new(:fallback, fn -> false end)
     |> assign_new(:retry, fn -> false end)
     |> assign_new(:cancel_label, fn -> gettext("Cancel") end)
     |> assign_new(:reason, fn -> nil end)
     |> assign_new(:execution, fn -> nil end)
     |> assign_new(:superagent, fn -> nil end)
     |> assign_new(:login, fn -> nil end)
     |> assign_new(:rerun, fn -> [] end)
     |> assign_new(:dir, fn -> nil end)
     |> assign_new(:notify, fn -> nil end)
     |> assign_new(:profile, fn -> nil end)
     |> assign_new(:port, fn -> nil end)
     |> then(
       &assign(
         &1,
         :question,
         Actions.phrase(action(&1.assigns), params(&1.assigns), AgentBoardWeb.Locale.language())
       )
     )}
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

      <div
        :if={@step == :confirm}
        class={["ab-act__confirm", @tone == :halt && "is-halt"]}
        role="group"
        aria-labelledby={"#{@id}-q"}
      >
        <p id={"#{@id}-q"} class="ab-act__question">{@question}</p>
        <div class="ab-act__buttons">
          <button
            :if={@mode == :stop_execution}
            id={"#{@id}-confirm"}
            type="button"
            class={["ab-btn ab-btn--sm", tone(@tone)]}
            phx-click="stop_execution"
            phx-value-id={@execution.id}
            phx-value-confirm={@question}
            phx-disable-with={@busy_label}
            phx-mounted={JS.focus()}
          >
            {@confirm_label}
          </button>
          <button
            :if={@mode == :stop}
            id={"#{@id}-confirm"}
            type="button"
            class={["ab-btn ab-btn--sm", tone(@tone)]}
            phx-click="act"
            phx-value-id={@task_id}
            phx-value-action="stop"
            phx-value-confirm={@question}
            phx-disable-with={@busy_label}
            phx-mounted={JS.focus()}
          >
            {@confirm_label}
          </button>
          <button
            :if={@mode not in [:stop, :stop_execution]}
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
            class="ab-btn ab-btn--sm"
            phx-click="cancel"
            phx-target={@myself}
          >
            {@cancel_label}
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

  def handle_event("cancel", _params, %{assigns: %{step: :confirm} = assigns} = socket) do
    :ok =
      Actions.decline(action(assigns), params(assigns), Actions.owner(:ui),
        language: AgentBoardWeb.Locale.language()
      )

    {:noreply, assign(socket, step: :idle, refocus: true)}
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, step: :idle, refocus: true)}

  # Only a confirmation starts the work, and only once; it carries the
  # sentence the person just read.
  def handle_event("go", _params, %{assigns: %{step: :confirm} = assigns} = socket) do
    {name, params, question} = {action(assigns), params(assigns), assigns.question}
    run = fn -> Actions.run(name, params, Actions.owner(:ui), confirm: question) end
    {:noreply, socket |> assign(step: :busy) |> start_async(:run, outliving_page(name, run))}
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

  def handle_async(:run, {:ok, {:ok, text}}, %{assigns: %{mode: mode}} = socket)
      when mode in [:grant_agent_access, :revoke_agent_access, :adopt_superagent] do
    send(self(), {:agent_access_done, text})
    {:noreply, assign(socket, step: :done, result: %{tone: :ok, text: text})}
  end

  def handle_async(:run, {:ok, {:ok, text}}, socket) do
    case socket.assigns.notify do
      {module, id} -> send_update(module, id: id, done: socket.assigns.mode, text: text)
      nil -> :ok
    end

    {:noreply, assign(socket, step: :done, result: %{tone: :ok, text: text})}
  end

  # The gate refused: what the person confirmed is no longer what would run.
  def handle_async(:run, {:ok, {:error, {refusal, _phrase}}}, socket)
      when refusal in [:unconfirmed, :phrase_changed] do
    text =
      gettext("Nothing happened: the action changed after confirmation. Check and confirm again.")

    {:noreply, assign(socket, step: :done, result: %{tone: :error, text: text})}
  end

  def handle_async(:run, {:ok, {:error, text}}, socket),
    do: {:noreply, assign(socket, step: :done, result: %{tone: :error, text: text})}

  def handle_async(:run, {:exit, reason}, socket) do
    text =
      gettext("The action did not finish: %{reason}",
        reason: AgentBoardWeb.FailureText.text(reason)
      )

    {:noreply, assign(socket, step: :done, result: %{tone: :error, text: text})}
  end

  # Provisioning takes minutes; closing the page must not cut it in half.
  defp outliving_page(:retry_provision_superagent, run), do: fn -> Superagents.detached(run) end
  defp outliving_page(_name, run), do: run

  defp action(%{mode: :retry}), do: :retry_ticket
  defp action(%{mode: :restart, superagent: %Superagent{}}), do: :start_superagent
  defp action(%{mode: :restart}), do: :start_agent
  defp action(%{mode: :dispatch}), do: :dispatch_task
  defp action(%{mode: :stop_execution}), do: :stop_execution
  defp action(%{mode: :start_superagent}), do: :start_superagent
  defp action(%{mode: :retry_provision_superagent}), do: :retry_provision_superagent
  defp action(%{mode: :stop_superagent}), do: :stop_superagent
  defp action(%{mode: :remove_superagent}), do: :remove_superagent
  defp action(%{mode: :clean_agent_leftovers}), do: :clean_agent_leftovers
  defp action(%{mode: :adopt_superagent}), do: :adopt_superagent
  defp action(%{mode: :grant_agent_access}), do: :grant_agent_access
  defp action(%{mode: :revoke_agent_access}), do: :revoke_agent_access
  defp action(%{mode: :stop}), do: :stop_task
  defp action(%{mode: :share_private}), do: :share_private_context

  defp params(%{mode: :retry} = assigns),
    do: %{
      ticket_id: assigns.ticket_id,
      repository_id: assigns.repository_id,
      number: assigns.number
    }

  defp params(%{mode: :restart, superagent: %Superagent{} = superagent}),
    do: %{superagent: superagent}

  defp params(%{mode: :restart}), do: %{}

  defp params(%{mode: :dispatch} = assigns) do
    %{
      task: assigns.task,
      executor: assigns.executor,
      ceiling_usd: assigns.ceiling_usd,
      fallback: assigns.fallback,
      retry: assigns.retry,
      reason: assigns.reason,
      repository: repository(assigns.task)
    }
  end

  defp params(%{mode: :stop, task: task}), do: %{task: task}

  defp params(%{mode: :share_private} = assigns),
    do: %{task: assigns.task, repository: repository(assigns.task), dir: assigns.dir}

  defp params(%{mode: :stop_execution} = assigns),
    do: %{execution: assigns.execution, task: assigns.task}

  defp params(%{mode: :grant_agent_access} = assigns),
    do: %{superagent: assigns.superagent, login: assigns.login, rerun: assigns.rerun}

  defp params(%{mode: :adopt_superagent} = assigns),
    do: %{profile: assigns.profile, port: assigns.port}

  defp params(%{mode: :revoke_agent_access} = assigns),
    do: %{superagent: assigns.superagent, login: assigns.login}

  defp params(%{mode: mode} = assigns)
       when mode in [
              :start_superagent,
              :stop_superagent,
              :remove_superagent,
              :retry_provision_superagent,
              :clean_agent_leftovers
            ],
       do: %{superagent: assigns.superagent}

  defp repository(%Task{repository: %Repository{} = repository}), do: repository
  defp repository(%Task{repository_id: id}) when is_integer(id), do: Board.repository(id)
  defp repository(_task), do: nil

  defp tone(:halt), do: "ab-btn--halt"
  defp tone(:primary), do: "ab-btn--primary"
  defp tone(_quiet), do: "ab-btn--quiet"
end
