defmodule AgentBoard.MergeGateTest do
  use ExUnit.Case, async: true

  test "the worker's merge command enforces the destination policy" do
    {output, status} =
      System.cmd("python3", ["-m", "unittest", "discover", "-s", "test/merge_gate"],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
