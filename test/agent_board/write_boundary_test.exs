defmodule AgentBoard.WriteBoundaryTest do
  @moduledoc """
  The web layer reads through the contexts and calls actions; it never writes
  the store, starts a runner or builds an Ecto query directly. The registry's
  red actions are the only door.
  """
  use ExUnit.Case, async: true

  @web_files Path.wildcard(Path.expand("../../lib/agent_board_web/**/*.ex", __DIR__))

  @patterns [
    {~r/\bRepo\.(insert|insert!|update|update!|delete|delete!|insert_all|update_all|delete_all)\(/,
     "Repo write"},
    {~r/\bBoard\.Requests\.(create_task|create_request)\(/, "request write"},
    {~r/\bBoard\.(stop_task|archive_task|resume_task|ask|add_repository|delete_repository|create_objective)\(/,
     "Board write"},
    {~r/\bRunners\.dispatch\(/, "runner dispatch"},
    {~r/\bSettings\.put\(/, "settings write"}
  ]

  test "the web layer reads through the contexts, not Repo" do
    assert @web_files != [], "the scan found no web files; check the path"

    offenders =
      for path <- @web_files,
          line <- File.stream!(path),
          Regex.match?(~r/\bRepo\./, line) do
        "#{path}: #{String.trim(line)}"
      end

    assert offenders == [],
           "the web layer reads through Board/Runners/Superagents, not Repo:\n" <>
             Enum.join(offenders, "\n")
  end

  test "the web layer has no direct write or dispatch" do
    assert @web_files != [], "the scan found no web files; check the path"

    offenders =
      for path <- @web_files,
          line <- File.stream!(path),
          {pattern, label} <- @patterns,
          Regex.match?(pattern, line) do
        "#{path}: #{label}: #{String.trim(line)}"
      end

    assert offenders == [], "the web layer must call an action:\n" <> Enum.join(offenders, "\n")
  end
end
