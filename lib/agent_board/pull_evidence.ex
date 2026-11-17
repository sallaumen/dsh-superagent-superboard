defmodule AgentBoard.PullEvidence do
  @moduledoc "Explicit, attributed PR comment reports. These never authorize a merge or replace GitHub reviews."
  alias AgentBoard.Workpad

  @sha ~r/\b[0-9a-f]{40}\b/i
  @validation ~r/^### (?:Validação|Validation)\s*$/imu
  @review ~r/\A## Independent (?:agent )?review(?: — final head)?\s*$/imu

  def parse(comments) do
    comments
    |> Enum.filter(&(&1["author_association"] in ~w(OWNER MEMBER COLLABORATOR)))
    |> Enum.sort_by(&{&1["updated_at"] || "", &1["id"] || 0})
    |> Enum.reduce(%{}, fn comment, reports ->
      text = visible(comment["body"] || "")

      reports
      |> put_report("ci", local_report(text), comment)
      |> put_report("review", review_report(text), comment)
    end)
  end

  defp put_report(reports, _kind, nil, _comment), do: reports

  defp put_report(reports, kind, report, comment) do
    Map.put(
      reports,
      kind,
      Map.merge(report, %{
        "author" => get_in(comment, ["user", "login"]),
        "url" => comment["html_url"],
        "at" => comment["updated_at"],
        "comment_id" => comment["id"]
      })
    )
  end

  defp visible(text) do
    text
    |> String.replace(~r/<!--.*?-->/s, "")
    |> String.replace(~r/^\s*(```|~~~).*?^\s*\1[^\n]*$/ms, "")
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(String.trim_leading(&1), ">"))
    |> Enum.join("\n")
    |> String.trim()
  end

  defp local_report(text) do
    case Regex.split(@validation, text, parts: 2) do
      [_, section] ->
        lines = section |> String.split(~r/^[#]{1,3} /m, parts: 2) |> hd() |> String.split("\n")

        gates = lines |> Enum.filter(&Regex.match?(~r/^\s*[-*] /, &1)) |> Enum.map(&gate/1)
        summarize(gates)

      _ ->
        nil
    end
  end

  defp gate(line) do
    case Regex.run(~r/^\s*[-*] `([^`\n]+)`\s*:\s*(.*)$/, line) do
      [_, command, result] ->
        %{
          "command" => command,
          "passed" => Workpad.reported_outcome(result),
          "sha" => sha(result)
        }

      _ ->
        %{"command" => String.trim(line), "passed" => nil, "sha" => nil}
    end
  end

  defp summarize(gates) do
    commits = gates |> Enum.map(& &1["sha"]) |> Enum.uniq()

    commit =
      case commits do
        [sha] when is_binary(sha) -> sha
        _ -> nil
      end

    %{
      "result" => gate_result(gates, commit),
      "sha" => commit,
      "commands" => Enum.map(gates, & &1["command"])
    }
  end

  defp gate_result(_, nil), do: "unknown"

  defp gate_result(gates, _) do
    cond do
      Enum.any?(gates, &(&1["passed"] == false)) -> "fail"
      Enum.all?(gates, &(&1["passed"] == true)) -> "pass"
      true -> "unknown"
    end
  end

  defp review_report(text) do
    if Regex.match?(@review, text) do
      reviewer =
        case Regex.run(~r/^Reviewer:\s*(.+)$/m, text) do
          [_, name] ->
            name
            |> String.split(~r/\.\s+(?:Approved head|Changes requested)/, parts: 2)
            |> hd()
            |> String.replace("`", "")
            |> String.slice(0, 240)

          _ ->
            nil
        end

      decision =
        Regex.run(
          ~r/(?:^|[.!?]\s+)(Approved head|Changes requested on head)\s+`?([0-9a-f]{40})\b/im,
          text
        )

      case {reviewer, decision} do
        {name, [_, verdict, commit]} when is_binary(name) ->
          %{
            "result" =>
              if(String.downcase(verdict) == "approved head",
                do: "approved",
                else: "changes_requested"
              ),
            "sha" => String.downcase(commit),
            "reviewer" => name
          }

        _ ->
          %{"result" => "unknown", "sha" => nil, "reviewer" => reviewer}
      end
    end
  end

  defp sha(text) do
    case Regex.scan(@sha, text) |> List.flatten() |> Enum.uniq() do
      [sha] -> String.downcase(sha)
      _ -> nil
    end
  end

  def state(report, head) do
    cond do
      not is_binary(report["sha"]) or not is_binary(head) -> "unknown"
      String.downcase(report["sha"]) != String.downcase(head) -> "stale"
      true -> report["result"]
    end
  end
end
