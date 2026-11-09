defmodule AgentBoard.Executors do
  @moduledoc """
  Who a task is for: the DeepSeek runner (`dsh`), Claude Code (`claude`) or
  Codex (`codex`), and what that means for the issue the board opens.

  The board only dispatches to the DeepSeek runner, and only by opening the
  issue with the bot's mention: the runner admits an issue from a listed
  sender that addresses it as an explicit request. An issue for Claude Code
  or Codex is opened without the mention and labelled `executor:<name>`, so
  the trail stays on GitHub and the runner has no explicit request to take.
  Choosing Claude Code or Codex records the choice; nothing starts them
  (docs/research/alfred.md, 3.5 and 3.6).

  Pure.
  """

  @executors ~w(dsh claude codex)
  @names %{"dsh" => "DeepSeek", "claude" => "Claude Code", "codex" => "Codex"}
  @mention ~r/\s*@sallaumen-agent\s*\z/i

  @doc "Every executor, in the board's fixed order."
  @spec all() :: [String.t()]
  def all, do: @executors

  @doc "The executor the board dispatched to before there was a choice."
  @spec default() :: String.t()
  def default, do: "dsh"

  @doc "Whether a value names an executor."
  @spec valid?(term()) :: boolean()
  def valid?(executor), do: executor in @executors

  @doc "The executor's name as the owner reads it."
  @spec name(String.t()) :: String.t()
  def name(executor), do: Map.fetch!(@names, executor)

  @doc "The label the issue carries."
  @spec label(String.t()) :: String.t()
  def label(executor) when executor in @executors, do: "executor:" <> executor

  @doc "Whether the board dispatches this executor itself (by the issue's mention)."
  @spec dispatched_by_board?(String.t()) :: boolean()
  def dispatched_by_board?(executor), do: executor == "dsh"

  @doc "A text that names the bot without calling it: the runner reads a mention as work."
  @spec without_mention(String.t()) :: String.t()
  def without_mention(text), do: String.replace(text, ~r/@(sallaumen-agent)\b/i, "\\1")

  @doc "The body of an issue that must not start anything yet."
  @spec held_body(String.t()) :: String.t()
  def held_body(body), do: body |> String.replace(@mention, "") |> without_mention()

  @doc """
  The issue body for an executor: the request's body with the bot's mention
  at the end for the DeepSeek runner, and without any mention for anyone
  else. A mention the caller already put at the end is not doubled; for
  another executor one inside the text loses its `@`, because the runner
  would read it as a request addressed to it.
  """
  @spec issue_body(String.t(), String.t()) :: String.t()
  def issue_body(body, executor) when executor in @executors do
    bare = body |> to_string() |> String.replace(@mention, "") |> String.trim_trailing()

    if dispatched_by_board?(executor),
      do: bare <> "\n\n@sallaumen-agent",
      else: without_mention(bare)
  end
end
