defmodule AgentBoard.ExecutorsTest do
  @moduledoc "Who a task is for, and the issue body each executor gets."
  use ExUnit.Case, async: true

  alias AgentBoard.Executors

  test "the DeepSeek runner's issue ends with the bot's mention, once" do
    assert Executors.issue_body("Add a boss", "dsh") == "Add a boss\n\n@sallaumen-agent"

    assert Executors.issue_body("Add a boss\n\n@sallaumen-agent\n", "dsh") ==
             "Add a boss\n\n@sallaumen-agent"
  end

  test "another executor's issue mentions nobody, even inside the text" do
    body = "Ask @sallaumen-agent later.\n\n@sallaumen-agent"

    for executor <- ["claude", "codex"] do
      result = Executors.issue_body(body, executor)
      refute result =~ "@sallaumen-agent"
      assert result == "Ask sallaumen-agent later."
    end
  end

  test "each executor has a label and a name; only the runner is dispatched by the board" do
    assert Enum.map(Executors.all(), &Executors.label/1) ==
             ["executor:dsh", "executor:claude", "executor:codex"]

    assert Enum.map(Executors.all(), &Executors.name/1) == ["DeepSeek", "Claude Code", "Codex"]
    assert Enum.filter(Executors.all(), &Executors.dispatched_by_board?/1) == ["dsh"]
    refute Executors.valid?("gpt")
  end
end
