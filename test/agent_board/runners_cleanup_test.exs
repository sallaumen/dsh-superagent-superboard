defmodule AgentBoard.RunnersCleanupTest do
  @moduledoc "O script de limpeza só remove execuções terminadas e antigas; dry-run por padrão."
  use ExUnit.Case, async: false

  @script Path.expand("../../scripts/runners/cleanup.sh", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "cleanup-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "done"))
    File.mkdir_p!(Path.join(root, "active"))
    File.write!(Path.join(root, "done/status"), "done\n")
    File.write!(Path.join(root, "active/status"), "running\n")
    File.touch!(Path.join(root, "done"), {{2020, 1, 1}, {0, 0, 0}})
    File.touch!(Path.join(root, "active"), {{2020, 1, 1}, {0, 0, 0}})
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "dry-run lists the finished run and keeps everything", %{root: root} do
    assert {output, 0} = run(root, ["--days=7"])
    assert output =~ "removeria"
    assert File.exists?(Path.join(root, "done"))
    assert File.exists?(Path.join(root, "active"))
  end

  test "apply removes only the finished run", %{root: root} do
    assert {_output, 0} = run(root, ["--days=7", "--apply"])
    refute File.exists?(Path.join(root, "done"))
    assert File.exists?(Path.join(root, "active"))
  end

  defp run(root, args) do
    System.cmd("/bin/bash", [@script | args],
      env: [{"RUNNER_ROOT", root}],
      stderr_to_stdout: true
    )
  end
end
