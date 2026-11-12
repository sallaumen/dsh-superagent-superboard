defmodule AgentBoardWeb.BoardComponents.Settings.ProjectPolicy do
  @moduledoc """
  A project's controls: whether its agent holds the board's instructions
  (`AgentBoard.Superagents.Policy`) and the button that applies them.

  The agent is read when the controls come into view and after an apply. The
  owner sees, per section, how many of the policy's rules the agent lacks and
  the rules only this agent has; a ticked rule stays as the project's own, the
  others are replaced. Nothing is applied without the click.
  """
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoard.Actions
  alias AgentBoard.Superagents.Policy
  alias AgentBoardWeb.{FailureText, Locale}

  @preview 160

  attr :superagent, :any, required: true
  attr :visible, :boolean, default: false

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, comparison: nil, error: nil, loading: false, notice: nil)}

  @impl true
  def update(assigns, socket) do
    showing = assigns[:visible] == true and socket.assigns[:visible] != true
    socket = assign(socket, assigns)
    {:ok, if(showing, do: load(socket), else: socket)}
  end

  defp load(socket) do
    superagent = socket.assigns.superagent

    socket
    |> assign(loading: true, error: nil)
    |> start_async(:compare, fn -> Policy.compare(superagent) end)
  end

  @impl true
  def handle_async(:compare, {:ok, {:ok, comparison}}, socket),
    do: {:noreply, assign(socket, comparison: comparison, loading: false)}

  def handle_async(:compare, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, comparison: nil, loading: false, error: reason)}

  def handle_async(:compare, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, comparison: nil, loading: false, error: :unreachable)}

  @impl true
  def handle_event("apply", params, socket) do
    keep = params |> Map.get("keep", []) |> List.wrap()

    # A write: it goes through the action registry, which records it.
    notice =
      case Actions.run(
             :apply_agent_policy,
             %{superagent: socket.assigns.superagent, keep: keep},
             Actions.owner(:ui),
             language: Locale.language()
           ) do
        {:ok, text} when is_binary(text) -> {:ok, text}
        {:error, text} when is_binary(text) -> {:error, text}
        {:error, reason} -> {:error, FailureText.text(reason)}
      end

    {:noreply, socket |> assign(notice: notice) |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={"project-#{@superagent.id}-policy"}
      class="ab-policy"
      aria-labelledby={"project-#{@superagent.id}-policy-title"}
    >
      <h5 id={"project-#{@superagent.id}-policy-title"}>{gettext("Agent's instructions")}</h5>

      <p
        :if={@notice}
        class={["ab-policy__notice", elem(@notice, 0) == :error && "is-error"]}
        role="status"
      >
        {elem(@notice, 1)}
      </p>
      <p :if={@loading and is_nil(@comparison)} class="ab-meta" role="status">
        {gettext("Reading the agent's instructions…")}
      </p>
      <p :if={@error} class="ab-meta">
        {gettext(
          "The agent did not answer, so the board cannot say whether its instructions are the policy."
        )}
      </p>

      <p :if={@comparison && @comparison.current?} class="ab-policy__state">
        <.glyph kind={:done} />{gettext("Up to date with the board's policy.")}
      </p>

      <form
        :if={@comparison && !@comparison.current?}
        id={"project-#{@superagent.id}-policy-form"}
        phx-submit="apply"
        phx-target={@myself}
      >
        <p class="ab-policy__state is-behind">
          <.glyph kind={:stale} />{gettext("Different from the board's policy.")}
        </p>
        <ul class="ab-policy__sections">
          <li :for={section <- @comparison.sections} :if={not section.current?}>
            <b>{section_label(section.name)}</b>
            <span class="ab-meta">{section_summary(section)}</span>
            <ul :if={section.own != []} class="ab-policy__lines">
              <li :for={line <- section.own}>
                <label>
                  <input type="checkbox" name="keep[]" value={line.id} />
                  <span>{gettext("Keep as a rule of this project")}</span>
                </label>
                <details>
                  <summary>{preview(line.text)}</summary>
                  <p>{line.text}</p>
                </details>
              </li>
            </ul>
          </li>
        </ul>
        <.project_rules sections={@comparison.sections} />
        <p class="ab-meta">
          {gettext(
            "Applying replaces the agent's three sections with the policy. A rule you do not tick is removed from this agent."
          )}
        </p>
        <button type="submit" class="ab-btn ab-btn--primary" phx-disable-with={gettext("Applying…")}>
          {gettext("Apply the policy to this agent")}
        </button>
      </form>

      <form
        :if={
          @comparison && @comparison.current? && Enum.any?(@comparison.sections, &(&1.rules != []))
        }
        id={"project-#{@superagent.id}-rules-form"}
        phx-submit="apply"
        phx-target={@myself}
      >
        <.project_rules sections={@comparison.sections} />
        <button type="submit" class="ab-btn" phx-disable-with={gettext("Applying…")}>
          {gettext("Save this project's rules")}
        </button>
      </form>
    </section>
    """
  end

  attr :sections, :list, required: true

  # The project's stored rules, ticked: unticking one drops it on the next save.
  defp project_rules(assigns) do
    assigns =
      assign(
        assigns,
        :rules,
        for(section <- assigns.sections, line <- section.rules, do: {section.name, line})
      )

    ~H"""
    <div :if={@rules != []} class="ab-policy__rules">
      <b>{gettext("Rules of this project")}</b>
      <ul class="ab-policy__lines">
        <li :for={{section, line} <- @rules}>
          <label>
            <input type="checkbox" name="keep[]" value={line.id} checked />
            <span>{section_label(section)}</span>
          </label>
          <details>
            <summary>{preview(line.text)}</summary>
            <p>{line.text}</p>
          </details>
        </li>
      </ul>
    </div>
    """
  end

  defp section_label("communication"), do: gettext("Communication")
  defp section_label("scope"), do: gettext("Ticket scope")
  defp section_label("delivery"), do: gettext("Delivery requirements")
  defp section_label(name), do: name

  defp section_summary(section) do
    [
      section.missing > 0 &&
        ngettext(
          "%{count} rule of the policy is missing or outdated",
          "%{count} rules of the policy are missing or outdated",
          section.missing
        ),
      section.own != [] &&
        ngettext(
          "%{count} rule only this agent has",
          "%{count} rules only this agent has",
          length(section.own)
        )
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> gettext("the text differs only in spacing")
      parts -> Enum.join(parts, " · ")
    end
  end

  defp preview(text) do
    if String.length(text) > @preview,
      do: String.slice(text, 0, @preview) <> "…",
      else: text
  end
end
