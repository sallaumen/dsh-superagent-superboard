defmodule AgentBoard.Executors.ToolInventoryTest do
  @moduledoc "What each executor has installed, by name, without the values that can hold keys."
  use ExUnit.Case, async: true

  alias AgentBoard.Executors.ToolInventory

  setup do
    home = Path.join(System.tmp_dir!(), "agent-tools-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(home) end)
    %{home: home}
  end

  defp write(home, path, text) do
    file = Path.join(home, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, text)
  end

  defp agent(inventory, id), do: Enum.find(inventory, &(&1.id == id))

  test "a home with nothing installed is empty lists, and the DeepSeek MCP is unread", %{
    home: home
  } do
    inventory = ToolInventory.inventory(home)

    assert %{skills: [], plugins: [], mcp: []} = agent(inventory, "claude_code")
    assert %{skills: [], plugins: [], mcp: []} = agent(inventory, "codex")
    assert %{skills: [], plugins: :unread, mcp: :unread} = agent(inventory, "dsh")
  end

  test "skills carry their description; a container is looked into; a dangling link is broken",
       %{home: home} do
    write(home, ".claude/skills/folded/SKILL.md", """
    ---
    name: folded
    description: >
      Reviews a change
      for bugs.
    ---
    body
    """)

    write(home, ".claude/skills/plain/SKILL.md", "---\ndescription: \"One line.\"\n---\n")
    # A folder that is not a skill: the synced skills live two levels down.
    write(home, ".claude/skills/synced/bucket/docx/SKILL.md", "---\ndescription: Word.\n---\n")
    write(home, ".claude/skills/synced/bucket/a/b/too-deep/SKILL.md", "---\n---\n")
    File.mkdir_p!(Path.join(home, ".claude/skills/empty"))
    File.ln_s!(Path.join(home, "gone"), Path.join(home, ".claude/skills/dangling"))

    assert [
             %{name: "dangling", ok?: false, description: nil},
             %{name: "docx", ok?: true, description: "Word."},
             %{name: "folded", ok?: true, description: "Reviews a change for bugs."},
             %{name: "plain", ok?: true, description: "One line."}
           ] = agent(ToolInventory.inventory(home), "claude_code").skills
  end

  test "Claude Code's servers and plugins are names; keys in env, args and URLs never leave",
       %{home: home} do
    write(home, ".claude.json", ~s({
      "mcpServers": {
        "memory": {"type": "stdio", "command": "/opt/bin/memory", "args": ["--token", "sk-ARGSECRET"],
                   "env": {"API_KEY": "sk-ENVSECRET"}},
        "remote": {"type": "http", "url": "https://mcp.example.com/v1?key=sk-URLSECRET",
                   "headers": {"Authorization": "Bearer sk-HEADERSECRET"}}
      }
    }))

    write(home, ".claude/plugins/installed_plugins.json", ~s({"plugins": {"a@m": [], "b@m": []}}))
    write(home, ".claude/settings.json", ~s({"enabledPlugins": {"a@m": true}}))

    claude = agent(ToolInventory.inventory(home), "claude_code")

    assert claude.mcp == [
             %{name: "memory", transport: "stdio", target: "memory"},
             %{name: "remote", transport: "http", target: "mcp.example.com"}
           ]

    assert claude.plugins == [%{name: "a@m", enabled?: true}, %{name: "b@m", enabled?: false}]
    refute inspect(claude) =~ "SECRET"
  end

  test "Codex's config.toml gives its servers and plugins, nested tables skipped", %{home: home} do
    write(home, ".codex/config.toml", """
    model = "gpt"

    [plugins."docs@openai"]
    enabled = true

    [plugins."off@openai"]
    enabled = false

    [mcp_servers.node_repl]
    command = "/usr/local/bin/node_repl"
    args = ["--key", "sk-ARGSECRET"]

    [mcp_servers.node_repl.env]
    TOKEN = "sk-ENVSECRET"

    [mcp_servers.docs]
    url = "https://developers.example.com/mcp?token=sk-URLSECRET"

    [desktop]
    command = "not a server"
    """)

    codex = agent(ToolInventory.inventory(home), "codex")

    assert codex.mcp == [
             %{name: "docs", transport: "http", target: "developers.example.com"},
             %{name: "node_repl", transport: "stdio", target: "node_repl"}
           ]

    assert codex.plugins == [
             %{name: "docs@openai", enabled?: true},
             %{name: "off@openai", enabled?: false}
           ]

    refute inspect(codex) =~ "SECRET"
  end

  test "a config that is not what it should be is unread, not empty", %{home: home} do
    write(home, ".claude.json", "{ not json")
    assert agent(ToolInventory.inventory(home), "claude_code").mcp == :unread
  end
end
