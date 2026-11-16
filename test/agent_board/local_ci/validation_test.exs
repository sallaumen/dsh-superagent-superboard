defmodule AgentBoard.LocalCI.ValidationTest do
  use ExUnit.Case, async: true

  alias AgentBoard.LocalCI.Validation

  test "matching full and abbreviated SHAs agree in either direction, ignoring case" do
    full = "abcdef1234567890abcdef1234567890abcdef12"
    assert Validation.state(%{sha: "ABCDEF1", passed?: true}, full) == :pass
    assert Validation.state(%{sha: full, passed?: false}, "ABCDEF1") == :fail
  end

  test "a known mismatch takes precedence over a pass or failure; missing evidence cannot contradict either" do
    for result <- [true, false] do
      assert Validation.state(%{sha: "aaaaaaa", passed?: result}, "bbbbbbb") == :stale
    end

    assert Validation.state(%{sha: nil, passed?: false}, "bbbbbbb") == :fail
    assert Validation.state(%{sha: "aaaaaaa", passed?: true}, nil) == :pass
  end
end
