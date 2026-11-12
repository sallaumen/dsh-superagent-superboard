defmodule AgentBoardWeb.BoardComponents.Settings.ProjectLeftovers do
  @moduledoc """
  A project's controls: the folders its ended tickets left on the disk
  (`AgentBoard.Superagents.Leftovers`), how long the project keeps them, and
  the red button that removes them all now.

  The folders are measured when the controls come into view and after a
  removal; nothing here removes on a timer. The daily retention belongs to
  the board (`Superagents.Ticker`), and this screen only says what it will
  take.
  """
  use AgentBoardWeb, :live_component

  alias AgentBoard.Actions
  alias AgentBoard.Superagents.Leftovers
  alias AgentBoardWeb.BoardComponents.AgentAction
  alias AgentBoardWeb.{FailureText, Locale, Numbers}

  attr :superagent, :any, required: true
  attr :visible, :boolean, default: false

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, survey: nil, error: nil, loading: false, notice: nil, days: nil)}

  @impl true
  # The red button finished: what the screen says is no longer on the disk,
  # and the button itself leaves when nothing is left, so the result is said
  # here.
  def update(%{done: _mode, text: text}, socket),
    do: {:ok, socket |> assign(notice: {:removed, text}) |> load()}

  def update(assigns, socket) do
    showing = assigns[:visible] == true and socket.assigns[:visible] != true
    socket = assign(socket, assigns)
    {:ok, if(showing, do: load(socket), else: socket)}
  end

  defp load(socket) do
    superagent = socket.assigns.superagent

    socket
    |> assign(loading: true, error: nil, days: Leftovers.days(superagent))
    |> start_async(:survey, fn -> Leftovers.survey(superagent) end)
  end

  @impl true
  def handle_async(:survey, {:ok, {:ok, survey}}, socket),
    do: {:noreply, assign(socket, survey: survey, loading: false)}

  def handle_async(:survey, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, survey: nil, loading: false, error: reason)}

  def handle_async(:survey, {:exit, reason}, socket),
    do: {:noreply, assign(socket, survey: nil, loading: false, error: reason)}

  @impl true
  def handle_event("keep", %{"days" => value}, socket) do
    # Anything that is not a number of days keeps the folders: the safe side.
    days =
      case Integer.parse(value) do
        {days, ""} -> days
        _ -> :never
      end

    # A write: it goes through the action registry, which records it.
    notice =
      case Actions.run(
             :set_agent_folder_days,
             %{superagent: socket.assigns.superagent, days: days},
             Actions.owner(:ui),
             language: Locale.language()
           ) do
        {:ok, text} -> {:ok, text}
        {:error, text} when is_binary(text) -> {:error, text}
        {:error, reason} -> {:error, FailureText.text(reason)}
      end

    {:noreply, assign(socket, notice: notice, days: Leftovers.days(socket.assigns.superagent))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={"project-#{@superagent.id}-leftovers"}
      class="ab-policy ab-leftovers"
      aria-labelledby={"project-#{@superagent.id}-leftovers-title"}
    >
      <h5 id={"project-#{@superagent.id}-leftovers-title"}>
        {gettext("Folders of ended tickets")}
      </h5>

      <p :if={match?({:removed, _text}, @notice)} class="ab-policy__notice" role="status">
        {elem(@notice, 1)}
      </p>
      <p :if={@loading and is_nil(@survey)} class="ab-meta" role="status">
        {gettext("Measuring the folders…")}
      </p>
      <p :if={@error} class="ab-meta">{error_text(@error)}</p>

      <div :if={@survey} class="ab-leftovers__facts">
        <p class="ab-policy__state">{held(@survey)}</p>
        <p :if={@survey.prs > 0} class="ab-meta">
          {ngettext(
            "%{count} pull request its agent opened is still open on a ticket that ended without a merge.",
            "%{count} pull requests its agent opened are still open on tickets that ended without a merge.",
            @survey.prs
          )}
        </p>
        <p :if={@survey.kept > 0} class="ab-meta">
          {ngettext(
            "%{count} more stays whatever you choose: an open ticket uses it, or it has uncommitted changes.",
            "%{count} more stay whatever you choose: an open ticket uses them, or they have uncommitted changes.",
            @survey.kept
          )}
        </p>
        <p :if={@survey.stray > 0} class="ab-meta">
          {ngettext(
            "%{count} folder belongs to no ticket the agent knows; the board never touches it.",
            "%{count} folders belong to no ticket the agent knows; the board never touches them.",
            @survey.stray
          )}
        </p>
        <p :if={@survey.problem} class="ab-meta">
          {gettext("The reading stopped before the end: %{reason}", reason: @survey.problem)}
        </p>
      </div>

      <form
        :if={@days}
        id={"project-#{@superagent.id}-leftovers-form"}
        class="ab-leftovers__keep"
        phx-change="keep"
        phx-target={@myself}
      >
        <label for={"project-#{@superagent.id}-leftovers-days"}>{gettext("Keep them for")}</label>
        <select id={"project-#{@superagent.id}-leftovers-days"} name="days" class="voice-select">
          <option :for={choice <- Leftovers.choices()} value={choice} selected={@days == choice}>
            {ngettext("%{count} day", "%{count} days", choice)}
          </option>
          <option value="never" selected={@days == :never}>
            {gettext("until I remove them")}
          </option>
        </select>
      </form>
      <p
        :if={@notice && elem(@notice, 0) != :removed}
        class={["ab-policy__notice", elem(@notice, 0) == :error && "is-error"]}
        role="status"
      >
        {elem(@notice, 1)}
      </p>
      <p :if={@days} class="ab-meta">{retention(@days, @survey)}</p>
      <p class="ab-meta">
        {gettext("Only the folders go. Each ticket, its issue, its pull request and its branch stay.")}
      </p>

      <.live_component
        :if={@survey && (@survey.folders != [] or @survey.prs > 0)}
        module={AgentAction}
        id={"project-clean-leftovers-#{@superagent.id}"}
        mode={:clean_agent_leftovers}
        tone={:halt}
        superagent={@superagent}
        label={gettext("Remove everything now…")}
        confirm_label={gettext("Remove everything")}
        cancel_label={gettext("Keep")}
        busy_label={gettext("Removing…")}
        notify={{__MODULE__, @id}}
      />
    </section>
    """
  end

  defp held(%{folders: []}), do: gettext("No folder of an ended ticket on the disk.")

  defp held(%{folders: folders, kb: kb}) do
    count = ngettext("%{count} folder", "%{count} folders", length(folders))
    if kb, do: "#{count} · #{Numbers.bytes(kb * 1024)}", else: count
  end

  defp retention(:never, _survey),
    do: gettext("The board removes nothing by itself: the folders stay until you remove them.")

  defp retention(days, survey) do
    rule =
      ngettext(
        "Once a day the board removes the folders of tickets that ended more than %{count} day ago.",
        "Once a day the board removes the folders of tickets that ended more than %{count} days ago.",
        days
      )

    if survey, do: rule <> " " <> past(survey.folders, days), else: rule
  end

  defp past(folders, days) do
    case length(Leftovers.past(folders, days, Date.utc_today())) do
      0 -> gettext("None is that old today.")
      n -> ngettext("%{count} is that old today.", "%{count} are that old today.", n)
    end
  end

  defp error_text(:unavailable),
    do: gettext("This board has no access to the agent's folders, so it cannot measure them.")

  defp error_text(reason),
    do: gettext("The folders could not be measured: %{reason}", reason: FailureText.text(reason))
end
