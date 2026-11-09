defmodule AgentBoard.GitHubNumberTest do
  use ExUnit.Case, async: true

  alias AgentBoard.GitHub

  test "reads a number the tables can hold, from text or an integer" do
    assert GitHub.number("42") == 42
    assert GitHub.number(42) == 42
    assert GitHub.number("2147483647") == 2_147_483_647
  end

  test "anything else is no number" do
    for value <- [
          "2147483648",
          "9999999999",
          2_147_483_648,
          0,
          -1,
          "abc",
          "",
          "4x",
          nil,
          %{},
          1.5
        ] do
      assert GitHub.number(value) == nil
    end
  end
end
