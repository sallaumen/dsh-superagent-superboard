defmodule AgentBoard.PipelineContractTest do
  @moduledoc """
  Guards the pipeline contract documented in PIPELINES.md.

  The CI jobs and the Makefile invoke these aliases; if this test fails,
  mix.exs drifted from the documentation and both must change together.
  """
  use ExUnit.Case, async: true

  defp aliases, do: Mix.Project.config()[:aliases]

  test "the local backend gate is check-only" do
    assert aliases()[:gate] == [
             "deps.unlock --check-unused",
             "hex.audit",
             "agent_kit.check",
             "compile --warnings-as-errors",
             "format --check-formatted",
             "credo --strict",
             "dialyzer",
             "test"
           ]
  end

  test "precommit runs the three gates with formatting in place" do
    precommit = aliases()[:precommit]
    assert "format" in precommit
    assert "credo --strict" in precommit
    # the type check runs here so no agent hands over a red Dialyzer
    assert "dialyzer" in precommit
    assert "test" in precommit
    refute "format --check-formatted" in precommit
  end

  test "lint is the fast, check-only pair" do
    assert aliases()[:lint] == ["format --check-formatted", "credo --strict"]
  end

  test "the test alias creates and migrates its own database" do
    # the backend CI jobs rely on this: no manual ecto steps in the workflow
    assert aliases()[:test] == ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
  end

  test "the frontend pipeline has setup, build and deploy steps" do
    for step <- [:"assets.setup", :"assets.build", :"assets.deploy"] do
      assert Keyword.get(aliases(), step) != nil, "alias #{step} ausente"
    end
  end

  test "the board requires the full local preflight and release, independent of Actions" do
    policy = Jason.decode!(File.read!(".github/superboard-merge.json"))
    assert policy["github"] == []
    assert Map.values(policy["local"]) == [["make", "-j1", "check", "release"]]
  end

  test "each PR gets one lightweight check without a database or dependency install" do
    workflow = File.read!(".github/workflows/ci.yml")
    assert workflow =~ "pull_request:"
    assert workflow =~ "workflow_dispatch:"
    assert workflow =~ "cancel-in-progress: true"
    assert workflow =~ "python3 -m unittest discover -s test/merge_gate"
    assert length(Regex.scan(~r/^    runs-on:/m, workflow)) == 1
    refute workflow =~ "mix deps.get"
    refute workflow =~ "services:"
  end

  test "shared practices have one authoring source and no copied consumer payload" do
    assert File.ls!("capabilities") |> Enum.sort() == ["README.md"]
    refute File.exists?("capabilities/skills")
    assert Path.wildcard(".elixir-agent-kit/library/**/*") |> Enum.filter(&File.regular?/1) == []
    assert Path.wildcard(".agents/skills/eak-*/SKILL.md") == []
    assert Path.wildcard(".claude/skills/eak-*/SKILL.md") == []
    assert File.read!(".elixir-agent-kit/START.md") =~ "../deps/elixir_agent_kit/priv/library/"

    for path <- ["Makefile", "scripts/ci-local.sh"] do
      content = File.read!(path)
      assert content =~ "mix agent_kit.check"
      refute content =~ "validar_biblioteca.py"
    end
  end
end
