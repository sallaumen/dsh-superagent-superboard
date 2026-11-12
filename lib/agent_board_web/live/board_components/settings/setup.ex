defmodule AgentBoardWeb.BoardComponents.Settings.Setup do
  @moduledoc """
  Settings → AI and setup: which AI does what, in three classes, whether each
  part is ready (`AgentBoard.Setup`) and the next step when one is not.

  Without a click the rows come from configuration only; "Check the setup"
  proves them with free reads, in the background, and only then.

  Below them, what each agent has installed on this machine: skills, plugins
  and MCP servers (`AgentBoard.AgentTools`), names only, read when the section
  comes into view.
  """
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoard.Actions
  alias AgentBoard.AgentTools
  alias AgentBoard.AI.Budget
  alias AgentBoard.Setup
  alias AgentBoard.Setup.Validation
  alias AgentBoardWeb.Time

  attr :active, :boolean, default: false
  attr :parent, :any, required: true
  attr :tz_offset, :integer, default: 0

  @impl true
  def mount(socket),
    do:
      {:ok,
       assign(socket,
         rows: nil,
         tools: [],
         checking: false,
         check_error: false,
         history: %{latest: nil, passed: nil}
       )}

  @impl true
  def update(%{validation_changed: true}, socket) do
    if socket.assigns[:active] do
      history = Validation.history()

      if history == socket.assigns.history,
        do: {:ok, socket},
        else: {:ok, assign(socket, history: history, rows: Setup.checklist())}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    showing = assigns[:active] == true and socket.assigns[:active] != true
    socket = assign(socket, assigns)

    # Current configuration and dated evidence are different readings. A token
    # removed since yesterday must show as missing even if yesterday's check passed.
    socket =
      if showing do
        assign(socket,
          rows: Setup.checklist(),
          history: Validation.history(),
          tools: AgentTools.inventory(),
          check_error: false
        )
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("check", _params, %{assigns: %{checking: true}} = socket),
    do: {:noreply, socket}

  def handle_event("check", _params, socket) do
    locale = Gettext.get_locale(AgentBoardWeb.Gettext)

    {:noreply,
     socket
     |> assign(checking: true, check_error: false)
     |> start_async(:check, fn ->
       # The rows carry sentences: the task has no locale of its own.
       Gettext.put_locale(AgentBoardWeb.Gettext, locale)
       Actions.run(:check_setup, %{}, Actions.owner(:ui))
     end)}
  end

  @impl true
  def handle_async(:check, {:ok, {:ok, {rows, history}}}, socket),
    do: {:noreply, assign(socket, rows: rows, checking: false, history: history)}

  def handle_async(:check, _unsuccessful, socket),
    do: {:noreply, assign(socket, checking: false, check_error: true)}

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
          class={["ab-btn", if(@history.latest, do: "ab-btn--sm", else: "ab-btn--primary")]}
          phx-click="check"
          phx-target={@myself}
          disabled={@checking}
        >
          {cond do
            @checking -> gettext("Checking...")
            @history.latest -> gettext("Check again")
            true -> gettext("Check the setup")
          end}
        </button>
        <p :if={last = @history.latest} id="setup-last-check" class="ab-meta" role="status">
          {gettext("Last validation:")}
          <time datetime={DateTime.to_iso8601(last.at)}>
            {Time.local_date(last.at, @tz_offset)} {Time.local_time(last.at, @tz_offset)}
          </time>
          · {if last.passed?, do: gettext("OK"), else: summary(last.counts)}
          <span :if={!last.passed? && @history.passed}>
            · {gettext("Last successful check:")}
            <time datetime={DateTime.to_iso8601(@history.passed.at)}>
              {Time.local_date(@history.passed.at, @tz_offset)} {Time.local_time(
                @history.passed.at,
                @tz_offset
              )}
            </time>
          </span>
        </p>
        <p :if={@check_error} class="ab-meta" role="alert">
          {gettext("Could not complete the check. Try again.")}
        </p>
        <a :if={@next} class="setup__jump" href={"#setup-row-#{@next.id}"}>
          {gettext("Next step: %{part}", part: @next.title)}
        </a>
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
            data-next={@next && @next.id == row.id}
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

      <section
        :if={@tools != []}
        id="setup-tools"
        class="settings-subpane setup__class"
        aria-labelledby="setup-tools-title"
      >
        <h4 id="setup-tools-title">{gettext("What each agent has installed")}</h4>
        <p class="settings-pane__intro">
          {gettext(
            "Skills, plugins and MCP servers found on this machine, by name. Keys and arguments are never read."
          )}
        </p>
        <details :for={agent <- @tools} id={"setup-tools-#{agent.id}"} class="setup__tools">
          <summary>
            <b>{agent.name}</b>
            <span class="ab-meta">{tools_summary(agent)}</span>
          </summary>
          <div class="setup__tool-lists">
            <.tool_list title={gettext("Skills")} items={agent.skills}>
              <:item :let={skill}>
                <span class="setup__tool-name">{skill.name}</span>
                <span :if={skill.ok?} class="ab-meta">{skill.description}</span>
                <span :if={not skill.ok?} class="setup__tool-broken">
                  <.glyph kind={:blocked} />{gettext(
                    "Broken: its link points to a folder that is gone."
                  )}
                </span>
              </:item>
            </.tool_list>
            <.tool_list title={gettext("MCP servers")} items={agent.mcp}>
              <:item :let={server}>
                <span class="setup__tool-name">{server.name}</span>
                <span class="ab-meta">
                  {Enum.join(Enum.reject([server.transport, server.target], &is_nil/1), " · ")}
                </span>
              </:item>
            </.tool_list>
            <.tool_list title={gettext("Plugins")} items={agent.plugins}>
              <:item :let={plugin}>
                <span class="setup__tool-name">{plugin.name}</span>
                <span :if={not plugin.enabled?} class="ab-meta">{gettext("turned off")}</span>
              </:item>
            </.tool_list>
          </div>
        </details>
      </section>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :any, required: true
  slot :item, required: true

  defp tool_list(assigns) do
    ~H"""
    <div class="setup__tool-list">
      <h5>{@title}</h5>
      <p :if={@items == :unread} class="ab-meta">{gettext("The board does not read this here.")}</p>
      <p :if={@items == []} class="ab-meta">{gettext("None installed.")}</p>
      <ul :if={is_list(@items) and @items != []}>
        <li :for={item <- @items}>{render_slot(@item, item)}</li>
      </ul>
    </div>
    """
  end

  # "37 skills · 1 broken · 4 MCP servers · 3 plugins"; a list the board does
  # not read is a question mark, never a zero.
  defp tools_summary(agent) do
    broken = if is_list(agent.skills), do: Enum.count(agent.skills, &(not &1.ok?)), else: 0

    [
      counted(
        agent.skills,
        &ngettext("%{count} skill", "%{count} skills", &1),
        gettext("? skills")
      ),
      broken > 0 && gettext("%{count} broken", count: broken),
      counted(
        agent.mcp,
        &ngettext("%{count} MCP server", "%{count} MCP servers", &1),
        gettext("? MCP servers")
      ),
      counted(
        agent.plugins,
        &ngettext("%{count} plugin", "%{count} plugins", &1),
        gettext("? plugins")
      )
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # Zero is said with the plural, as people write it ("0 plugins").
  defp counted([], text, _unread), do: String.replace(text.(2), "2", "0", global: false)
  defp counted(items, text, _unread) when is_list(items), do: text.(length(items))
  defp counted(_items, _text, unread), do: unread

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
  defp state_word(:configured), do: gettext("Configured")
  defp state_word(:missing), do: gettext("Missing")
  defp state_word(:off), do: gettext("Off")
  defp state_word(:failed), do: gettext("Failed")
  defp state_word(_state), do: pgettext("status", "No answer")

  defp summary(counts) do
    [
      {counts["ok"], &ngettext("%{count} ready", "%{count} ready", &1)},
      {(counts["failed"] || 0) + (counts["missing"] || 0),
       &ngettext("%{count} to fix", "%{count} to fix", &1)},
      {counts["off"], &ngettext("%{count} off", "%{count} off", &1)},
      {counts["unknown"],
       &ngettext("%{count} without an answer", "%{count} without an answer", &1)}
    ]
    |> Enum.filter(fn {count, _word} -> is_integer(count) and count > 0 end)
    |> Enum.map_join(", ", fn {count, word} -> word.(count) end)
  end
end
