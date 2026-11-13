defmodule AgentBoard.Superagents.AlpineRuntimeTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Superagents.AlpineRuntime

  @tag :tmp_dir
  test "checks the subprocess dependency resolved by the selected Harness", %{tmp_dir: tmp} do
    dsh = Path.join(tmp, "bin/dsh")
    package = Path.join(tmp, "node_modules/@deepseek-ai/dsh-subprocess-local")
    dep = Path.join(package, "node_modules/koffi")
    File.mkdir_p!(Path.dirname(dsh))
    File.mkdir_p!(dep)
    File.touch!(dsh)
    File.touch!(Path.join(package, "index.js"))

    File.write!(Path.join(dep, "index.js"), "process.exit(134)")
    assert {:error, {:setup, native}} = AlpineRuntime.probe(dsh)
    assert native =~ "Koffi"

    File.write!(Path.join(dep, "index.js"), "process.exit(42)")
    assert {:error, {:setup, manager}} = AlpineRuntime.probe(dsh)
    assert manager =~ "Node 22"

    File.write!(Path.join(dep, "index.js"), "process.exit(0)")
    assert AlpineRuntime.probe(dsh) == :ok
  end
end
