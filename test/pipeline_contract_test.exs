defmodule AgentBoard.PipelineContractTest do
  @moduledoc """
  Guards the pipeline contract documented in PIPELINES.md.

  The CI jobs and the Makefile invoke these aliases; if this test fails,
  mix.exs drifted from the documentation and both must change together.
  """
  use ExUnit.Case, async: true

  defp aliases, do: Mix.Project.config()[:aliases]

  test "gate is check-only and mirrors the CI gates job" do
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

  test "every alias the CI invokes exists" do
    # mirrors .github/workflows/ci.yml: backend runs gate; frontend runs the
    # assets steps; the release job runs compile/phx.digest/release directly.
    for alias_name <- [:gate, :"assets.setup", :"assets.build", :"assets.deploy"] do
      assert Keyword.get(aliases(), alias_name) != nil,
             "alias #{inspect(alias_name)} ausente"
    end
  end

  defp workflow do
    File.read!(Path.join(File.cwd!(), ".github/workflows/ci.yml"))
  end

  test "the workflow has the five pipeline jobs" do
    for job <- ["gates", "backend", "frontend", "library", "release"] do
      assert String.contains?(workflow(), "\n  #{job}:"),
             "job #{job} ausente no ci.yml"
    end
  end

  test "the workflow cancels stale runs and supports manual dispatch" do
    assert String.contains?(workflow(), "workflow_dispatch:")
    assert String.contains?(workflow(), "concurrency:")
    assert String.contains?(workflow(), "cancel-in-progress: true")
  end

  test "the workflow enforces the same commands the local pipelines run" do
    wf = workflow()

    for command <- [
          "mix compile --warnings-as-errors",
          "mix format --check-formatted",
          "mix credo --strict",
          "mix deps.unlock --check-unused",
          "mix hex.audit",
          "mix agent_kit.check",
          "mix test --partitions 4",
          "check_assets.sh",
          "mix assets.setup",
          "mix assets.build",
          "mix assets.deploy",
          "mix phx.digest",
          "mix release --overwrite"
        ] do
      assert String.contains?(wf, command), "comando ausente no ci.yml: #{command}"
    end
  end

  test "shared practices have one authoring source and no copied consumer payload" do
    assert File.ls!("capabilities") |> Enum.sort() == ["README.md"]
    refute File.exists?("capabilities/skills")
    assert Path.wildcard(".elixir-agent-kit/library/**/*") |> Enum.filter(&File.regular?/1) == []
    assert Path.wildcard(".agents/skills/eak-*/SKILL.md") == []
    assert Path.wildcard(".claude/skills/eak-*/SKILL.md") == []
    assert File.read!(".elixir-agent-kit/START.md") =~ "../deps/elixir_agent_kit/priv/library/"

    for path <- ["Makefile", "scripts/ci-local.sh", ".github/workflows/ci.yml"] do
      content = File.read!(path)
      assert content =~ "mix agent_kit.check"
      refute content =~ "validar_biblioteca.py"
    end
  end
end
