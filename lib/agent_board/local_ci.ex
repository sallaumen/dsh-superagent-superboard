defmodule AgentBoard.LocalCI do
  @moduledoc """
  The local gate the executor actually ran, read from its own reports.

  GitHub Actions is unavailable for this account because of the billing limit,
  so a red remote check is not evidence that the code failed. When an agent
  report says `mix precommit` passed (tests, format, Credo), that is the
  trustworthy signal. The board only reads what the report says; a missing
  statement stays unknown.

  Reports are text written by the executor. This module extracts the PR
  numbers they name, the local state and a short excerpt for the hover. It
  never invents a run that is not in the text.
  """

  @pr ~r/(?:PR\s*#|pull\/)(\d+)/i
  @pass ~r/\b(passed|passes|green|0 failures|0 issues)\b/i
  @fail ~r/\b(failed|failing)\b|[1-9]\d*\s+(failures|issues)/i
  @billing ~r/(billing|spending limit)/i
  @actions ~r/GitHub Actions|CI did not run|CI could not (start|run)/i
  @report_limit 220

  @type status :: %{
          state: :pass | :fail,
          detail: String.t(),
          remote_blocked: boolean(),
          at: DateTime.t() | nil
        }

  @doc "Local CI status by PR number for one repository."
  @spec by_pr(struct(), [map()]) :: %{optional(integer()) => status()}
  def by_pr(repository, tickets) do
    slug = "#{repository.owner}/#{repository.name}"

    tickets
    |> Enum.filter(&same_repo?(&1, slug))
    |> Enum.reduce(%{}, fn ticket, acc ->
      ticket
      |> own_statuses()
      |> Enum.reduce(acc, fn {number, status}, inner ->
        Map.put(inner, number, status)
      end)
    end)
  end

  defp own_statuses(ticket) do
    ticket
    |> Map.get("reports", [])
    |> Enum.sort_by(&(&1["at"] || ~U[1970-01-01 00:00:00Z]))
    |> Enum.flat_map(fn report ->
      case local_state(report["summary"] || "") do
        nil ->
          []

        state ->
          status = %{
            state: state,
            detail: detail(report["summary"] || ""),
            remote_blocked: remote_blocked?(report["summary"] || ""),
            at: report["at"]
          }

          report |> pr_numbers() |> Enum.map(&{&1, status})
      end
    end)
    |> Map.new()
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
    |> Enum.map(fn [_, number] -> String.to_integer(number) end)
  end

  defp local_state(summary) do
    precommit =
      summary
      |> String.split(~r/(?<=[.!?])\s+|\n+/)
      |> Enum.filter(&(&1 =~ ~r/mix precommit/i))

    cond do
      Enum.any?(precommit, &(&1 =~ @fail)) -> :fail
      Enum.any?(precommit, &(&1 =~ @pass)) -> :pass
      true -> nil
    end
  end

  defp detail(summary) do
    summary
    |> String.split(~r/(?<=[.!?])\s+|\n+/)
    |> Enum.find(&(&1 =~ ~r/mix precommit/i))
    |> case do
      nil -> "mix precommit"
      text -> text |> String.replace(~r/\s+/, " ") |> String.trim()
    end
    |> String.slice(0, @report_limit)
  end

  defp remote_blocked?(summary), do: summary =~ @actions and summary =~ @billing
end
