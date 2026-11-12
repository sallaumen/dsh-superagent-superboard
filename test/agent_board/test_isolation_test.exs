defmodule AgentBoard.TestIsolationTest do
  @moduledoc "Two runs of the suite at once never share a temporary path."
  use ExUnit.Case, async: true

  alias AgentBoard.Board.PrivateContext

  test "this run's temporary folder is its own, named by the OS process" do
    assert Path.basename(System.tmp_dir!()) == "agent-board-test-run-#{System.pid()}"
    assert File.dir?(System.tmp_dir!())
  end

  test "the private contexts live inside it" do
    assert String.starts_with?(PrivateContext.root(), System.tmp_dir!())
  end
end
