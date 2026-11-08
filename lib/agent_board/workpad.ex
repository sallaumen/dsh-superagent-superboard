defmodule AgentBoard.Workpad do
  @moduledoc """
  The agent's workpad: one comment per issue, edited in place, that says in
  fixed sections what the agent plans, what it validated, what it asks and
  what blocks it (`docs/agent/prompts/communication.md`).

  The board reads the sections by name, not by phrasing. A comment without
  the heading is not a workpad and `parse/1` returns `nil`, so the callers
  fall back to the text heuristics they used before. An empty or missing
  section is `nil`: the parser never invents a question, a block or a gate.
  """

  @heading ~r/^[ \t]*##[ \t]+Relat[óo]rio do agente[ \t]*$/miu
  @section ~r/^[ \t]*###[ \t]+(.+?)[ \t]*$/u
  @fence ~r/^[ \t]*(?:```|~~~)/
  @hidden ~r/<!--.*?-->/s
  @pr ~r/(?:PR\s*#|pull\/)(\d+)/i
  @placeholder ~r/^(?:[-–—*_]+|n\/a|none|nenhum[ao]?|\(?vazi[oa]\)?|\(none\)|\(empty\))$/iu
  @pass ~r/\b(passou|passaram|passed|passes|pass|ok|verde|green)\b|\b0\s+(failures?|falhas?|issues?|erros?|errors?)\b/iu
  @fail ~r/\b(falhou|falharam|failed|failing|fail|vermelho|red)\b|\b[1-9]\d*\s+(failures?|falhas?|issues?|erros?|errors?)\b/iu
  @sha ~r/\b(?=[0-9a-f]*\d)[0-9a-f]{7,40}\b/i
  @command ~r/^`?([^`:\n]{1,80}?)`?\s*:\s*(.+)$/u
  @list_marker ~r/^(?:[-*+]|\d+[.)])\s+/

  @typedoc "One gate, as the Validação section states it; `passed?` is nil when the line names no result."
  @type validation :: %{
          command: String.t() | nil,
          passed?: boolean() | nil,
          sha: String.t() | nil,
          detail: String.t()
        }

  @typedoc "The four sections, nil when empty, plus the PR numbers the comment names anywhere."
  @type t :: %{
          plan: String.t() | nil,
          validation: validation() | nil,
          question: String.t() | nil,
          blockage: String.t() | nil,
          pull_requests: [integer()]
        }

  @doc """
  The workpad in a comment body, or nil when the body is not one.

  The heading may follow other text (the automated-agent line the policy
  requires). Only `###` headings split sections, so markdown inside a section
  (lists, code, deeper headings) stays in it. Section names are matched in
  Portuguese and English, without case.
  """
  @spec parse(term()) :: t() | nil
  def parse(body) when is_binary(body) do
    text = String.replace(body, @hidden, "")

    case Regex.split(@heading, text, parts: 2) do
      [_before, rest] ->
        sections = sections(rest)

        %{
          plan: section(sections, ~w(plano plan)),
          validation: sections |> section(~w(validação validacao validation)) |> validation(),
          question: section(sections, ~w(pergunta question)),
          blockage: section(sections, ~w(bloqueio blockage blocker block)),
          pull_requests: pull_requests(text)
        }

      _no_heading ->
        nil
    end
  end

  def parse(_other), do: nil

  @doc """
  Whether a text asks the person something: a real question mark, not a mood.

  The fallback for an agent comment that is not a workpad (the sections are
  the strong signal). The runner's hidden marker is not part of the message,
  so callers strip it before asking; a question mark inside a code block is
  still a question mark, as it was before the workpad.
  """
  @spec question?(term()) :: boolean()
  def question?(text) when is_binary(text), do: String.contains?(text, "?")
  def question?(_text), do: false

  # One pass over the lines: a `###` line opens a section, everything else
  # (including `###` inside a fenced block) belongs to the open one, and the
  # text before the first heading is dropped.
  defp sections(rest) do
    {sections, _fence?} =
      rest
      |> String.split("\n")
      |> Enum.reduce({[], false}, &section_line/2)

    sections
    |> Enum.reverse()
    |> Enum.map(fn {name, lines} -> {name, lines |> Enum.reverse() |> Enum.join("\n")} end)
  end

  defp section_line(line, {sections, fence?}) do
    heading = if fence?, do: nil, else: heading_name(line)

    cond do
      heading -> {[{heading, []} | sections], false}
      line =~ @fence -> {append(sections, line), not fence?}
      true -> {append(sections, line), fence?}
    end
  end

  defp append([], _line), do: []
  defp append([{name, lines} | rest], line), do: [{name, [line | lines]} | rest]

  defp heading_name(line) do
    case Regex.run(@section, line) do
      [_, name] -> section_name(name)
      nil -> nil
    end
  end

  defp section_name(name) do
    name
    |> String.replace(~r/[`*_]/, "")
    |> String.trim()
    |> String.trim_trailing(":")
    |> String.trim()
    |> String.downcase()
  end

  defp section(sections, names) do
    case Enum.find(sections, fn {name, _body} -> name in names end) do
      {_name, body} -> content(body)
      nil -> nil
    end
  end

  # An empty section, or one holding only a placeholder, says nothing.
  defp content(body) do
    text = String.trim(body)

    if text == "" or text =~ @placeholder, do: nil, else: text
  end

  # The gate line: the one naming `mix precommit` when there are several,
  # else the first. A list item or a `command: result` line starts a gate; a
  # bare line continues the previous one (a wrapped line), fences are
  # dropped. `command: result` splits on the first colon; the sha is any hex
  # token of seven or more characters holding a digit.
  defp validation(nil), do: nil

  defp validation(text) do
    gates =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or &1 =~ @fence))
      |> Enum.reduce([], &gate_line/2)
      |> Enum.reverse()

    line =
      gates
      |> Enum.find(&(&1 =~ ~r/mix precommit/i))
      |> Kernel.||(List.first(gates) || "")
      |> String.replace(~r/\s+/, " ")

    {command, result} =
      case Regex.run(@command, line) do
        [_, command, result] -> {String.trim(command), result}
        nil -> {nil, line}
      end

    %{command: command, passed?: passed?(result), sha: sha(line), detail: line}
  end

  defp gate_line(line, gates) do
    stripped = String.replace(line, @list_marker, "")

    if gates == [] or stripped != line or stripped =~ @command do
      [stripped | gates]
    else
      [hd(gates) <> " " <> stripped | tl(gates)]
    end
  end

  defp passed?(result) do
    cond do
      result =~ @fail -> false
      result =~ @pass -> true
      true -> nil
    end
  end

  defp sha(line) do
    case Regex.run(@sha, line) do
      [sha] -> String.downcase(sha)
      nil -> nil
    end
  end

  defp pull_requests(text) do
    @pr
    |> Regex.scan(text)
    |> Enum.map(fn [_, number] -> String.to_integer(number) end)
    |> Enum.uniq()
  end
end
