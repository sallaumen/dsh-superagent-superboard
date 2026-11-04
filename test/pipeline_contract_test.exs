defmodule AgentBoard.PipelineContractTest do
  @moduledoc """
  Guards the pipeline contract documented in PIPELINES.md.

  The CI jobs and the Makefile invoke these aliases; if this test fails,
  mix.exs drifted from the documentation and both must change together.
  """
  use ExUnit.Case, async: true

  defp aliases, do: Mix.Project.config()[:aliases]

  test "gate is check-only and runs the three gates" do
    assert aliases()[:gate] == [
             "compile --warnings-as-errors",
             "format --check-formatted",
             "credo --strict",
             "test"
           ]
  end

  test "precommit runs the three gates with formatting in place" do
    precommit = aliases()[:precommit]
    assert "format" in precommit
    assert "credo --strict" in precommit
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

  test "every alias the CI invokes exists" do
    # mirrors .github/workflows/ci.yml: backend runs gate; frontend runs the
    # assets steps; the release job runs compile/phx.digest/release directly.
    for alias_name <- [:gate, :"assets.setup", :"assets.build", :"assets.deploy"] do
      assert Keyword.get(aliases(), alias_name) != nil,
             "alias #{inspect(alias_name)} ausente"
    end
  end
end
