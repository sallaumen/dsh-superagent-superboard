defmodule AgentBoard.LocalCI do
  @moduledoc """
  The local gate the executor actually ran, read from its own reports.

  A failed remote check alone does not identify the cause or the outcome of
  local validation. A missing local report stays unknown.

  Reports are text written by the executor. This module extracts the PR
  numbers they name, the local state and a short excerpt for the hover. It
  never invents a run that is not in the text.

  The agent's workpad (`AgentBoard.Workpad`) says the same in a field: its
  Validação names the command, the result and the sha it ran on. When a
  ticket's issue has a workpad whose Validação names a result, that is the
  ticket's gate and the reports are not read; a gate on another commit than
  the PR's head is `:stale`, shown as unknown, never as a pass. Without a
  workpad, or with Validação empty, the reports decide as before.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.LocalCI.{Report, Validation}

  @pr ~r/(?:PR\s*#|pull\/)(\d+)/i
  @billing ~r/(billing|spending limit)/i
  @actions ~r/GitHub Actions|CI did not run|CI could not (start|run)/i
  @report_limit 220

  @type status :: %{
          state: :pass | :fail | :stale,
          detail: String.t(),
          remote_blocked: boolean(),
          at: DateTime.t() | nil,
          scope: :pr | :ticket | :workpad,
          evidence_pr: integer() | nil
        }

  @doc """
  Local CI status by PR number for one repository.

  Options: `:workpads`, the workpad per issue number (`Board.agent_workpads/1`),
  preferred over the reports of that issue's ticket when its Validação names
  a result; `:heads`, the head sha per PR number (`Board.pull_heads/1`), to
  check the sha the gate ran on. A workpad whose issue has no ticket still
  counts: the comment is on GitHub, the ticket in the runner's sqlite.
  """
  @spec by_pr(struct(), [map()], keyword()) :: %{optional(integer()) => status()}
  def by_pr(repository, tickets, opts \\ []) do
    workpads = Keyword.get(opts, :workpads, %{})
    heads = Keyword.get(opts, :heads, %{})
    slug = "#{repository.owner}/#{repository.name}"
    own = Enum.filter(tickets, &same_repo?(&1, slug))
    covered = own |> Enum.flat_map(&(&1["numbers"] || [])) |> MapSet.new()

    from_tickets =
      Enum.reduce(own, %{}, fn ticket, acc ->
        Map.merge(acc, own_statuses(ticket, workpads, heads))
      end)

    explicit =
      workpads
      |> Enum.reject(fn {number, _workpad} -> MapSet.member?(covered, number) end)
      |> Enum.reduce(from_tickets, fn {_number, workpad}, acc ->
        Map.merge(workpad_statuses(%{}, workpad, heads), acc)
      end)

    # A direct workpad or ticket/report link always takes precedence.
    Map.merge(unlinked_statuses(own, workpads, heads), explicit)
  end

  defp unlinked_statuses(tickets, workpads, heads) do
    linked =
      tickets
      |> Enum.filter(&(ticket_prs(&1) != []))
      |> Enum.flat_map(&(&1["numbers"] || []))
      |> MapSet.new()

    by_head = Enum.group_by(heads, fn {_pr, sha} -> String.downcase(sha) end, &elem(&1, 0))

    candidates =
      for {issue, %{pull_requests: [], validation: %{passed?: verdict, sha: sha} = gate}} <-
            workpads,
          is_boolean(verdict) and is_binary(sha),
          not MapSet.member?(linked, issue),
          String.match?(sha, ~r/\A[0-9a-f]{40}\z/i),
          [pr] <- [Map.get(by_head, String.downcase(sha))],
          do: {pr, gate}

    candidates
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reduce(%{}, fn {pr, gates}, acc ->
      case Enum.uniq_by(gates, & &1.passed?) do
        [gate] -> Map.put(acc, pr, workpad_status(gate, Map.fetch!(heads, pr)))
        _conflicting -> acc
      end
    end)
  end

  defp own_statuses(ticket, workpads, heads) do
    case ticket_workpad(ticket, workpads) do
      %{validation: %{passed?: passed?}} = workpad when is_boolean(passed?) ->
        workpad_statuses(ticket, workpad, heads)

      %{validation: %{command: command, passed?: nil}} when is_binary(command) ->
        # A named check has no verdict yet. An older report cannot complete it.
        %{}

      _no_gate ->
        report_statuses(ticket)
    end
  end

  defp ticket_workpad(ticket, workpads) do
    Enum.find_value(ticket["numbers"] || [], &Map.get(workpads, &1))
  end

  # An empty Validação is no gate: the workpad contributes no status, and
  # there is no report to fall back to when its issue has no ticket.
  defp workpad_statuses(_ticket, %{validation: nil}, _heads), do: %{}
  defp workpad_statuses(_ticket, %{validation: %{passed?: nil}}, _heads), do: %{}

  # The workpad's gate covers every PR the ticket names and every PR the
  # workpad names, each checked against its own head.
  defp workpad_statuses(ticket, workpad, heads) do
    (ticket_prs(ticket) ++ workpad.pull_requests)
    |> Enum.uniq()
    |> Map.new(&{&1, workpad_status(workpad.validation, Map.get(heads, &1))})
  end

  defp workpad_status(validation, head) do
    state = Validation.state(validation, head)

    %{
      state: state,
      detail: workpad_detail(state, validation, head),
      remote_blocked: remote_blocked?(validation.detail),
      at: nil,
      scope: :workpad,
      evidence_pr: nil,
      sha: validation.sha,
      head_sha: head
    }
  end

  defp workpad_detail(:stale, validation, head) do
    String.slice(validation.detail, 0, @report_limit) <>
      gettext(", but the PR's head is %{head}: the gate does not cover the current commit.",
        head: String.slice(head, 0, 7)
      )
  end

  defp workpad_detail(_state, validation, _head),
    do: String.slice(validation.detail, 0, @report_limit)

  defp ticket_prs(ticket) do
    Enum.flat_map(Map.get(ticket, "reports", []), &pr_numbers/1) ++
      Map.get(ticket, "own_threads", [])
  end

  defp report_statuses(ticket) do
    reports =
      ticket
      |> Map.get("reports", [])
      |> Enum.sort_by(&(&1["at"] || ~U[1970-01-01 00:00:00Z]))

    local =
      reports
      |> Enum.flat_map(fn report ->
        case Report.gate(report["summary"] || "") do
          nil -> []
          gate -> [{report, gate}]
        end
      end)

    direct =
      local
      |> Enum.flat_map(fn {report, gate} ->
        report
        |> pr_numbers()
        |> Enum.map(&{&1, status(report, gate, :pr, nil)})
      end)
      |> Map.new()

    case List.last(local) do
      nil ->
        direct

      {report, gate} ->
        # A ticket is one unit of work: a later PR it names is covered by the
        # ticket's local gate even when that PR has no line of its own. The
        # tooltip names the evidence PR so the scope is explicit.
        evidence = report |> pr_numbers() |> List.first()

        ticket_status = status(report, gate, :ticket, evidence)

        reports
        |> Enum.flat_map(&pr_numbers/1)
        |> Enum.uniq()
        |> Enum.reject(&Map.has_key?(direct, &1))
        |> Enum.reduce(direct, fn number, acc -> Map.put(acc, number, ticket_status) end)
    end
  end

  defp status(report, gate, scope, evidence) do
    %{
      state: gate.state,
      detail: String.slice(gate.detail, 0, @report_limit),
      remote_blocked: remote_blocked?(report["summary"] || ""),
      at: report["at"],
      scope: scope,
      evidence_pr: evidence
    }
  end

  defp same_repo?(ticket, slug) do
    prefix = "https://github.com/#{slug}/"

    Enum.any?(ticket["channel_urls"] || [], &String.starts_with?(&1, prefix)) or
      Enum.any?(ticket["reports"] || [], fn report ->
        String.contains?(report["summary"] || "", "github.com/#{slug}/")
      end)
  end

  defp pr_numbers(report) do
    @pr
    |> Regex.scan(report["summary"] || "")
    |> Enum.map(fn [_, number] -> AgentBoard.GitHub.number(number) end)
    |> Enum.reject(&is_nil/1)
  end

  defp remote_blocked?(summary), do: summary =~ @actions and summary =~ @billing
end
