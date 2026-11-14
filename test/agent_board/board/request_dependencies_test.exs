defmodule AgentBoard.Board.RequestDependenciesTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.RequestDependencies

  test "a DSH request names its blocker and waits for release" do
    request = %{executor: "dsh", depends_on: ["a"], body: "Fix the display", language: "pt"}

    assert {:ok, %{held: true, body: body}} = RequestDependencies.prepare(request, %{"a" => 101})
    assert String.starts_with?(body, "**Depende de:** #101\n")
    assert String.ends_with?(body, request.body)
  end

  test "a Codex request names its blocker without being held" do
    request = %{executor: "codex", depends_on: ["a"], body: "Fix the display", language: "pt"}

    assert {:ok, prepared} = RequestDependencies.prepare(request, %{"a" => 101})
    assert String.starts_with?(prepared.body, "**Depende de:** #101\n")
    refute prepared[:held]
  end

  test "one failed blocker prevents creation even when another has an issue number" do
    request = %{executor: "dsh", depends_on: ["a", "b"], body: "Fix the display"}

    assert {:error, :dependency_failed} =
             RequestDependencies.prepare(request, %{"a" => 101, "b" => :failed})
  end
end
