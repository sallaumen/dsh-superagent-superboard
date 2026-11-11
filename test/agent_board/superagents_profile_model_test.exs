defmodule AgentBoard.SuperagentsProfileModelTest do
  @moduledoc "The model a superagent's profile gives its agent, read and never written."
  use ExUnit.Case, async: true

  alias AgentBoard.Superagents
  alias AgentBoard.Superagents.Superagent

  setup do
    root = Path.join(System.tmp_dir!(), "profiles-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "superagent-x"))
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "the agent-default-model block names the model", %{root: root} do
    File.write!(Path.join([root, "superagent-x", "cordis.patch.yml"]), """
    - id: ui-settings
      config:
        model: not-this-one
    - id: agent-default-model
      name: "@deepseek-ai/dsh-agent-default-model"
      config:
        provider: deepseek-account
        model: deepseek-flash
        reasoningEffort: high
    - id: other
      config:
        port: 3083
    """)

    assert Superagents.profile_model(%Superagent{profile: "superagent-x"}, root) ==
             "deepseek-flash"
  end

  test "a profile without the block, or without the file, has no model", %{root: root} do
    File.write!(
      Path.join([root, "superagent-x", "cordis.patch.yml"]),
      "- id: other\n  config:\n    port: 1\n"
    )

    assert Superagents.profile_model(%Superagent{profile: "superagent-x"}, root) == nil
    assert Superagents.profile_model(%Superagent{profile: "missing"}, root) == nil
  end
end
