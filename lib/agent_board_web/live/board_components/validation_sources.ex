defmodule AgentBoardWeb.BoardComponents.ValidationSources do
  @moduledoc "Inspectable origins of reported PR validation, kept apart from native GitHub checks."
  use AgentBoardWeb, :html
  alias AgentBoard.Lanes.Review
  alias AgentBoard.PullEvidence

  attr :pull, :map, required: true

  def sources(assigns) do
    assigns = assign(assigns, :reports, Map.get(assigns.pull, :reported_evidence) || %{})

    ~H"""
    <details :if={@reports != %{}} class="ab-validation-sources">
      <summary>{gettext("Validation sources")}</summary>
      <p class="ab-meta">
        {gettext("GitHub checks")}: {checks(@pull.checks_state)} · {gettext("GitHub review")}: {Review.native(
          @pull.review_state
        )}
      </p>
      <ul>
        <li :for={kind <- ["ci", "review"]} :if={@reports[kind]}>
          <% report = @reports[kind] %>
          <strong>{kind_label(kind)}: {result(PullEvidence.state(report, @pull.head_sha))}</strong>
          <p>{gettext("Reported by %{author}", author: report["author"] || "?")}</p>
          <p :if={report["reviewer"]}>
            {gettext("Reviewer named in the report")}: {report["reviewer"]}
          </p>
          <p>
            {gettext("Reported commit")}:
            <code title={report["sha"]}>{short_sha(report["sha"])}</code>
          </p>
          <p :if={PullEvidence.state(report, @pull.head_sha) == "stale"}>
            {gettext("PR head")}: <code title={@pull.head_sha}>{short_sha(@pull.head_sha)}</code>
          </p>
          <ul :if={kind == "ci"}>
            <li :for={command <- report["commands"] || []}><code>{command}</code></li>
          </ul>
          <a href={report["url"]} target="_blank" rel="noopener noreferrer">{gettext(
            "Open source comment"
          )}</a>
        </li>
      </ul>
      <p class="ab-meta">
        {gettext(
          "Reports describe checks and reviews performed outside GitHub. The board has not independently verified their execution; they do not replace required GitHub approvals."
        )}
      </p>
    </details>
    """
  end

  defp short_sha(nil), do: gettext("not provided")
  defp short_sha(sha), do: String.slice(sha, 0, 7)

  defp kind_label("ci"), do: gettext("Local CI")
  defp kind_label("review"), do: gettext("Independent review")
  defp result("pass"), do: gettext("passed")
  defp result("fail"), do: gettext("failed")
  defp result("approved"), do: gettext("approved")
  defp result("changes_requested"), do: gettext("changes requested")
  defp result("stale"), do: gettext("outdated commit")
  defp result(_), do: gettext("incomplete report")
  defp checks("success"), do: gettext("passed")
  defp checks("failure"), do: gettext("failed")
  defp checks("pending"), do: gettext("running")
  defp checks("none"), do: gettext("none configured")
  defp checks(_), do: gettext("not read")
end
