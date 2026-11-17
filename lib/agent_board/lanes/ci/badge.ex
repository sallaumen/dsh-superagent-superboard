defmodule AgentBoard.Lanes.CI.Badge do
  @moduledoc "The state, label and supporting detail shared by the board's CI indicators."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.CI

  @doc "Describe the verdict in the reader's locale; only a local pass sets the local flag."
  @spec describe(PullRequest.t(), map() | nil) :: %{
          state: String.t(),
          note: String.t(),
          title: String.t(),
          local: boolean()
        }
  def describe(pull, local) do
    {state, reason} = CI.classify(pull, local)
    {note, title} = ci_words(reason, pull, local)

    %{
      state: Atom.to_string(state),
      note: note,
      title: title,
      local: CI.local_result(local) == :pass
    }
  end

  defp ci_words(:local_pass, _pull, %{scope: :pr_comment} = local),
    do: {gettext("Local CI reported: passed"), local.detail}

  defp ci_words(:local_fail, _pull, %{scope: :pr_comment} = local),
    do: {gettext("Local CI reported: failed"), local.detail}

  defp ci_words(:incomplete, _pull, local),
    do: {gettext("Local CI report incomplete"), local.detail}

  defp ci_words(:local_pass, pull, local),
    do: {gettext("Local CI passed"), local_title(local, pull)}

  defp ci_words(:local_fail, _pull, local),
    do: {gettext("Local CI failed"), gettext("Local CI failed: %{detail}", detail: local.detail)}

  defp ci_words(:stale, _pull, local), do: {gettext("Local CI unknown"), local.detail}

  defp ci_words(:remote_failure, pull, _local),
    do: {gettext("Local CI unknown"), remote_failure_title(pull)}

  defp ci_words(:remote_pass, _pull, _local),
    do: {gettext("CI passed"), gettext("GitHub Actions passed.")}

  defp ci_words(:pending, _pull, _local),
    do: {gettext("CI running"), gettext("GitHub Actions is still running.")}

  defp ci_words(:no_checks, _pull, _local),
    do: {gettext("no CI"), gettext("No remote check configured.")}

  defp local_title(local, pull) do
    prefix =
      if local.remote_blocked do
        gettext("%{remote} (billing/no credit on GitHub).", remote: remote_label(pull))
      else
        "#{remote_label(pull)}."
      end

    gettext("%{prefix} Local CI passed%{scope}: %{detail}",
      prefix: prefix,
      scope: local_scope(local),
      detail: local.detail
    )
  end

  defp remote_label(%{checks_state: "failure"}), do: gettext("GitHub Actions failed")
  defp remote_label(%{checks_state: "success"}), do: gettext("GitHub Actions passed")
  defp remote_label(%{checks_state: "pending"}), do: gettext("GitHub Actions is still running")
  defp remote_label(_pull), do: gettext("GitHub Actions has no checks")

  defp local_scope(%{scope: :ticket, evidence_pr: number}),
    do:
      " " <>
        gettext("on the ticket (report cites #%{number}; this PR is from the same work)",
          number: number
        )

  defp local_scope(_local), do: ""

  defp remote_failure_title(pull) do
    case checks_label(pull) do
      "" ->
        gettext("GitHub Actions failed; no evidence of local CI.")

      checks ->
        gettext(
          "GitHub Actions failed on %{checks}; no evidence of local CI.",
          checks: checks
        )
    end
  end

  defp checks_label(%PullRequest{checks_failed: failed}) when is_binary(failed) do
    failed
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(" #{gettext("and")} ")
    |> String.slice(0, 80)
  end

  defp checks_label(_pull), do: ""
end
