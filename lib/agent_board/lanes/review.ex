defmodule AgentBoard.Lanes.Review do
  @moduledoc "Keep native GitHub decisions separate from an attributed independent-review report."
  use Gettext, backend: AgentBoardWeb.Gettext

  @type verdict :: {:native | :reported, String.t() | nil}

  @doc "Prefer a native decision; otherwise classify the report against the current PR head."
  @spec classify(map()) :: verdict()
  def classify(%{review_state: state}) when state in ["approved", "changes_requested"],
    do: {:native, state}

  def classify(pull) do
    case get_in(Map.get(pull, :reported_evidence) || %{}, ["review"]) do
      nil -> {:native, Map.get(pull, :review_state)}
      report -> {:reported, AgentBoard.PullEvidence.state(report, pull.head_sha)}
    end
  end

  @doc "Describe the review while keeping reported evidence distinct from native decisions."
  @spec label(map()) :: String.t()
  def label(pull) do
    case classify(pull) do
      {:native, state} -> native(state)
      {:reported, "approved"} -> gettext("Independent review reported")
      {:reported, "changes_requested"} -> gettext("Changes requested in report")
      {:reported, "stale"} -> gettext("Review report outdated")
      {:reported, _} -> gettext("Review report incomplete")
    end
  end

  def native("approved"), do: gettext("approved")
  def native("changes_requested"), do: gettext("changes requested")
  def native("pending"), do: gettext("review pending")
  def native(_), do: gettext("no review")
end
