defmodule AgentBoardWeb.BoardComponents.MergeProgress do
  @moduledoc "The check evidence for one PR; parallel work stays visible as separate rows."
  use AgentBoardWeb, :html

  attr :snapshot, :map, default: nil
  attr :compact, :boolean, default: false

  def progress(assigns) do
    ~H"""
    <section
      :if={@snapshot || !@compact}
      class="ab-merge-progress"
      aria-label={gettext("Merge checks")}
    >
      <%= if @snapshot do %>
        <strong>{headline(@snapshot)}</strong>
        <small :if={!@compact} class="ab-meta">{gettext("Checked revision")} · {String.slice(
          @snapshot["head"],
          0,
          8
        )}</small>
        <ul :if={!@compact && @snapshot["checks"] != []}>
          <li :for={row <- @snapshot["checks"]}>
            <span>{row["name"]}</span>
            <small class="ab-meta">{if row["source"] == "local", do: gettext("Local"), else: "GitHub"} · {label(
              row["state"]
            )}</small>
          </li>
        </ul>
        <p :if={!@compact && @snapshot["review_required"] == true}>
          {if @snapshot["review"] == "APPROVED",
            do: gettext("Review approved"),
            else: gettext("Approval required on this revision")}
        </p>
      <% else %>
        <span class="ab-meta">{gettext("No merge check record for this PR yet.")}</span>
      <% end %>
    </section>
    """
  end

  defp headline(%{"state" => "stale"}), do: gettext("Waiting for checks on the current revision")

  defp headline(%{"state" => "unconfirmed"}),
    do: gettext("No recent signal · last observed checks below")

  defp headline(%{"state" => "merging"}), do: gettext("Checks passed · merging")
  defp headline(%{"state" => "merged"}), do: gettext("Checks passed · merged")

  defp headline(%{"state" => "blocked", "reason" => reason}) when reason != "checks_outstanding",
    do: reason(reason)

  defp headline(snapshot) do
    rows = snapshot["checks"]
    failed = Enum.find(rows, &(&1["state"] == "failed"))
    running = Enum.count(rows, &(&1["state"] == "running"))
    outstanding = Enum.count(rows, &(&1["state"] != "passed"))

    cond do
      failed ->
        gettext("Merge blocked · %{name} failed", name: failed["name"])

      snapshot["state"] == "blocked" ->
        ngettext(
          "Merge waiting · 1 check outstanding",
          "Merge waiting · %{count} checks outstanding",
          outstanding
        )

      running > 0 ->
        ngettext("1 check running", "%{count} checks running in parallel", running)

      outstanding > 0 ->
        gettext("Waiting for required checks")

      true ->
        gettext("Verifying merge conditions")
    end
  end

  defp reason("review_required"), do: gettext("Merge blocked · review required")
  defp reason("policy_unavailable"), do: gettext("Merge blocked · project policy unavailable")
  defp reason("revision_changed"), do: gettext("Merge blocked · revision changed")
  defp reason("worktree_changed"), do: gettext("Merge blocked · working copy changed")

  defp reason("not_current_worker_pr"),
    do: gettext("Merge blocked · PR does not match this execution")

  defp reason("github_blocks_merge"), do: gettext("Merge blocked by GitHub")
  defp reason(_), do: gettext("Merge blocked · verification incomplete")

  defp label("running"), do: gettext("Running")
  defp label("queued"), do: gettext("Queued")
  defp label("passed"), do: gettext("Passed")
  defp label("failed"), do: gettext("Failed")
  defp label("missing"), do: gettext("Not reported")
  defp label("ambiguous"), do: gettext("Multiple matching checks")
  defp label(_), do: gettext("Pending")
end
