defmodule AgentBoardWeb.BoardComponents.Settings.Setup do
  @moduledoc """
  Settings → AI and setup: which AI does what, in three classes, whether each
  part is ready (`AgentBoard.Setup`) and the next step when one is not.

  Without a click the rows come from configuration only; "Check the setup"
  proves them with free reads, in the background, and only then.
  """
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoard.AI.Budget
  alias AgentBoard.Setup
  alias AgentBoardWeb.Time

  attr :active, :boolean, default: false
  attr :parent, :any, required: true
  attr :tz_offset, :integer, default: 0

  @impl true
  def mount(socket), do: {:ok, assign(socket, rows: nil, checking: false, checked_at: nil)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # Configuration only, read when the section shows; a check's result stays.
    socket =
      if assigns[:active] and is_nil(socket.assigns.checked_at),
        do: assign(socket, rows: Setup.checklist()),
        else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("check", _params, socket) do
    locale = Gettext.get_locale(AgentBoardWeb.Gettext)

    {:noreply,
     socket
     |> assign(checking: true)
     |> start_async(:check, fn ->
       # The rows carry sentences: the task has no locale of its own.
       Gettext.put_locale(AgentBoardWeb.Gettext, locale)
       Setup.verify()
     end)}
  end

  @impl true
  def handle_async(:check, {:ok, rows}, socket),
    do: {:noreply, assign(socket, rows: rows, checking: false, checked_at: DateTime.utc_now())}

  def handle_async(:check, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, checking: false)}

  @impl true
  def render(assigns) do
    rows = assigns.rows || []

    assigns =
      assigns
      |> assign(:next, Setup.next_step(rows))
      |> assign(:by_class, Enum.group_by(rows, & &1.class))

    ~H"""
    <div class="setup">
      <div class="setup__check">
        <button
          id="setup-check"
          type="button"
          class="ab-btn ab-btn--primary"
          phx-click="check"
          phx-target={@myself}
          disabled={@checking}
        >
          {if @checking, do: gettext("Checking..."), else: gettext("Check the setup")}
        </button>
        <p class="ab-meta" aria-live="polite">
          <%= cond do %>
            <% @checking -> %>
              {gettext("Asking GitHub, the AI provider, each agent and the CLIs. Nothing is spent.")}
            <% @checked_at -> %>
              {gettext("Checked at %{time}: %{summary}",
                time: Time.local_time(@checked_at, @tz_offset),
                summary: summary(@rows)
              )}
            <% true -> %>
              {gettext(
                "Not checked yet: a key that is set may still be refused. The check reads, it never spends."
              )}
          <% end %>
        </p>
      </div>

      <div :if={@next} id="setup-next" class="setup__next" role="status">
        <b>{gettext("Next step:")}</b>
        <span>{@next.title}. {@next.detail}</span>
        <.fix fix={@next.fix} parent={@parent} />
      </div>

      <section
        :for={{class, title, text, sections} <- classes()}
        :if={@by_class[class]}
        id={"setup-class-#{class}"}
        class="settings-subpane setup__class"
        aria-labelledby={"setup-class-#{class}-title"}
      >
        <h4 id={"setup-class-#{class}-title"}>{title}</h4>
        <p class="settings-pane__intro">{text}</p>
        <ul class="setup__rows">
          <li
            :for={row <- @by_class[class]}
            id={"setup-row-#{row.id}"}
            class="setup__row"
            data-state={row.state}
          >
            <span class={["setup__state", "setup__state--#{row.state}"]}>
              <.glyph kind={mark(row.state)} />{state_word(row.state)}
            </span>
            <div class="setup__what">
              <b>{row.title}</b>
              <span class="ab-meta">{row.detail}</span>
              <span :if={use = when_to_use(row.id)} class="setup__use">{use}</span>
            </div>
            <.fix :if={row.state not in [:ok, :configured]} fix={row.fix} parent={@parent} />
          </li>
        </ul>
        <p :if={sections != []} class="setup__more">
          <button
            :for={{section, label} <- sections}
            type="button"
            class="ab-more"
            phx-click="select_section"
            phx-value-section={section}
            phx-target={@parent}
          >
            {label}
          </button>
        </p>
      </section>
    </div>
    """
  end

  attr :fix, :map, default: nil
  attr :parent, :any, required: true

  defp fix(%{fix: nil} = assigns), do: ~H""

  defp fix(%{fix: %{href: _}} = assigns) do
    ~H"""
    <a class="ab-btn ab-btn--sm setup__fix" href={@fix.href} target="_blank" rel="noopener noreferrer">
      {@fix.label} <.icon name="hero-arrow-top-right-on-square" class="size-3" />
    </a>
    """
  end

  defp fix(%{fix: %{section: _}} = assigns) do
    ~H"""
    <button
      type="button"
      class="ab-btn ab-btn--sm setup__fix"
      phx-click="select_section"
      phx-value-section={@fix.section}
      phx-target={@parent}
    >
      {@fix.label}
    </button>
    """
  end

  defp fix(%{fix: %{command: _}} = assigns) do
    ~H"""
    <span class="setup__fix setup__fix--command">
      {gettext("In the Terminal:")} <code>{@fix.command}</code>
    </span>
    """
  end

  # Who the AI works for, what it costs and where its details are.
  defp classes do
    [
      {:work, gettext("Who does the work"),
       gettext(
         "The agents that write the code of each task, on GitHub. DeepSeek takes the issues by itself; Claude Code and Codex run on this Mac when you dispatch a task."
       ), [{"projects", gettext("Projects")}, {"execution", gettext("Execution and ceilings")}]},
      {:board_ai, gettext("The board's own AI"),
       gettext(
         "Refines and splits your requests, answers questions, suggests unblocks and talks by voice. It pays per use with the API key, and stops at the daily ceiling of %{tokens} tokens.",
         tokens: AgentBoardWeb.Numbers.grouped(Budget.cap())
       ), [{"execution", gettext("Its calls and costs")}]},
      {:voice, gettext("Voice"),
       gettext(
         "Speaking and listening. ElevenLabs sounds better and spends the plan's credits; without it the browser speaks and listens for free."
       ), [{"voice", gettext("Voice and summary")}]}
    ]
  end

  defp when_to_use(:deepseek_agents),
    do:
      gettext(
        "For everyday tasks: one agent per project, all day, paid by the DeepSeek account in the agent's profile."
      )

  defp when_to_use(:claude),
    do:
      gettext(
        "For large or delicate tasks. It runs on the Max subscription: no charge per task, but usage has a limit."
      )

  defp when_to_use(:codex),
    do:
      gettext(
        "When Claude Code is near its limit, or for a second opinion. It spends the ChatGPT plan's weekly quota."
      )

  defp when_to_use(_id), do: nil

  defp mark(:ok), do: :done
  defp mark(:configured), do: :queue
  defp mark(:off), do: :queue
  defp mark(:failed), do: :blocked
  defp mark(:missing), do: :blocked
  defp mark(_state), do: :unknown

  defp state_word(:ok), do: gettext("Ready")
  defp state_word(:configured), do: gettext("Set, not checked")
  defp state_word(:missing), do: gettext("Missing")
  defp state_word(:off), do: gettext("Off")
  defp state_word(:failed), do: gettext("Failed")
  defp state_word(_state), do: pgettext("status", "No answer")

  defp summary(rows) do
    counts = Enum.frequencies_by(rows, & &1.state)

    [
      {counts[:ok], &ngettext("%{count} ready", "%{count} ready", &1)},
      {(counts[:failed] || 0) + (counts[:missing] || 0),
       &ngettext("%{count} to fix", "%{count} to fix", &1)},
      {counts[:off], &ngettext("%{count} off", "%{count} off", &1)},
      {counts[:unknown],
       &ngettext("%{count} without an answer", "%{count} without an answer", &1)}
    ]
    |> Enum.filter(fn {count, _word} -> is_integer(count) and count > 0 end)
    |> Enum.map_join(", ", fn {count, word} -> word.(count) end)
  end
end
