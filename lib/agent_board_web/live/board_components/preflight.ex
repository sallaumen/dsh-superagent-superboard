defmodule AgentBoardWeb.BoardComponents.Preflight do
  @moduledoc "Local preflight evidence for the running card and task inspector."
  use AgentBoardWeb, :html

  attr :snapshot, :map, default: nil
  attr :compact, :boolean, default: false

  def progress(assigns) do
    ~H"""
    <section :if={@snapshot} class="ab-merge-progress" aria-label={gettext("Local preflight")}>
      <strong>{headline(@snapshot)}</strong>
      <small :if={!@compact} class="ab-meta">
        {gettext("Starting revision")} · {String.slice(@snapshot.head, 0, 8)}
      </small>
      <ul :if={!@compact}>
        <li :for={{stage, status} <- @snapshot.rows} aria-current={status == "running" && "step"}>
          <span>{name(stage)}<small
            :if={@snapshot[:reasons] && @snapshot.reasons[stage]}
            class="ab-check-reason"
          >{why(@snapshot.reasons[stage], status)}</small></span>
          <small class="ab-meta">{label(status)}</small>
        </li>
      </ul>
      <p :if={!@compact && @snapshot[:ui_reason]} class="ab-meta">
        {reason(@snapshot.ui_reason)}
        <span :if={@snapshot.stage == "ui_review"}>{result(@snapshot)}</span>
      </p>
    </section>
    <.progress :if={!@compact && @snapshot && @snapshot[:other]} snapshot={@snapshot.other} />
    """
  end

  def why(_, "not_run"), do: gettext("A previous step stopped the run.")
  def why("disabled", _), do: gettext("Disabled in project settings.")
  def why("unrelated", _), do: gettext("No changed files match this check.")

  def why("matched:" <> pattern, _),
    do: gettext("Changed file matches %{pattern}.", pattern: pattern)

  def why("matched", _), do: gettext("The task changed files covered by this check.")

  def why("unknown_diff", _),
    do: gettext("The change could not be compared; running as a precaution.")

  def why("required", _), do: gettext("Required for every task in this project.")
  def why(_, _), do: nil

  defp headline(%{state: "skipped"}), do: gettext("No applicable project checks")
  defp headline(%{kind: :project, state: "passed"}), do: gettext("Project checks passed")

  defp headline(%{kind: :project, stage: stage, state: state}),
    do: gettext("Project checks: %{stage} · %{status}", stage: name(stage), status: label(state))

  defp headline(%{state: "passed"}), do: gettext("Local preflight passed")

  defp headline(%{stage: stage, state: state}),
    do: gettext("Local preflight: %{stage} · %{status}", stage: name(stage), status: label(state))

  defp reason("interaction"), do: gettext("UI review: browser interaction code changed.")
  defp reason("appearance"), do: gettext("UI review: styles or visual assets changed.")
  defp reason("screen"), do: gettext("UI review: a screen, component or route changed.")
  defp reason("copy"), do: gettext("UI review: interface translations changed.")

  defp reason("unknown"),
    do: gettext("UI review: the change could not be compared with the base branch.")

  defp reason("none"), do: gettext("UI review not needed: no interface files changed.")
  defp reason(_), do: nil

  defp result(%{state: "passed"}),
    do:
      gettext(
        "WebKit checked the board, inspector, request form and settings on desktop and mobile."
      )

  defp result(%{state: "failed", ui_failure: screen})
       when screen in ~w(board inspector composer settings),
       do: gettext("Browser check failed: %{screen}.", screen: screen_label(screen))

  defp result(%{state: "failed"}),
    do:
      gettext(
        "The browser check failed. See the local preflight output for the failing interaction."
      )

  defp result(%{state: "unavailable"}),
    do: gettext("The test board or WebKit could not start. The interface was not verified.")

  defp result(_), do: nil

  defp screen_label("board"), do: gettext("Board")
  defp screen_label("inspector"), do: gettext("Task inspector")
  defp screen_label("composer"), do: gettext("Request form")
  defp screen_label("settings"), do: gettext("Settings")

  defp name("ui_review"), do: gettext("UI review")
  defp name("backend"), do: gettext("Backend")
  defp name("frontend"), do: gettext("Frontend")
  defp name("library"), do: gettext("Practice library")

  defp name(id) do
    {:ok, command} = AgentBoard.ProjectStages.command(id)
    Enum.join(command, " ")
  end

  defp label("running"), do: gettext("Running")
  defp label("passed"), do: gettext("Passed")
  defp label("failed"), do: gettext("Failed")
  defp label("unavailable"), do: gettext("Unavailable")
  defp label("skipped"), do: gettext("Skipped")
  defp label("pending"), do: gettext("Pending")
  defp label("not_run"), do: gettext("Not run")
  defp label("interrupted"), do: gettext("Interrupted")
  defp label("unconfirmed"), do: gettext("No recent signal")
end
