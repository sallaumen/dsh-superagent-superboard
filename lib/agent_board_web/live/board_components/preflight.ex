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
          <span>{name(stage)}</span>
          <small class="ab-meta">{label(status)}</small>
        </li>
      </ul>
    </section>
    """
  end

  defp headline(%{state: "passed"}), do: gettext("Local preflight passed")

  defp headline(%{stage: stage, state: state}),
    do: gettext("Local preflight: %{stage} · %{status}", stage: name(stage), status: label(state))

  defp name("backend"), do: gettext("Backend")
  defp name("frontend"), do: gettext("Frontend")
  defp name("library"), do: gettext("Practice library")
  defp label("running"), do: gettext("Running")
  defp label("passed"), do: gettext("Passed")
  defp label("failed"), do: gettext("Failed")
  defp label("pending"), do: gettext("Pending")
  defp label("not_run"), do: gettext("Not run")
  defp label("interrupted"), do: gettext("Interrupted")
  defp label("unconfirmed"), do: gettext("No recent signal")
end
