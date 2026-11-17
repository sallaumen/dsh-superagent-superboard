defmodule AgentBoard.Lanes.Review do
  @moduledoc "Keep native GitHub decisions separate from an attributed independent-review report."
  use Gettext, backend: AgentBoardWeb.Gettext

  def label(%{review_state: state}) when state in ["approved", "changes_requested"],
    do: native(state)

  def label(pull) do
    case get_in(Map.get(pull, :reported_evidence) || %{}, ["review"]) do
      nil ->
        native(Map.get(pull, :review_state))

      report ->
        case AgentBoard.PullEvidence.state(report, pull.head_sha) do
          "approved" -> gettext("Independent review reported")
          "changes_requested" -> gettext("Changes requested in report")
          "stale" -> gettext("Review report outdated")
          _ -> gettext("Review report incomplete")
        end
    end
  end

  def native("approved"), do: gettext("approved")
  def native("changes_requested"), do: gettext("changes requested")
  def native("pending"), do: gettext("review pending")
  def native(_), do: gettext("no review")
end
