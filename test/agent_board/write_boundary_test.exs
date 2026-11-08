defmodule AgentBoard.WriteBoundaryTest do
  @moduledoc """
  The web layer reads and calls actions; it never writes the store or starts a
  runner directly. The registry's red actions are the only door.
  """
  use ExUnit.Case, async: true

  @web_files Path.wildcard("lib/agent_board_web/**/*.ex")

  @patterns [
    {~r/\bRepo\.(insert|insert!|update|update!|delete|delete!|insert_all|update_all|delete_all)\(/,
     "Repo write"},
    {~r/\bBoard\.(create_task|create_request|stop_task|archive_task|resume_task|ask|add_repository|delete_repository|create_objective)\(/,
     "Board write"},
    {~r/\bRunners\.dispatch\(/, "runner dispatch"},
    {~r/\bSettings\.put\(/, "settings write"}
  ]

  test "the web layer has no direct write or dispatch" do
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
