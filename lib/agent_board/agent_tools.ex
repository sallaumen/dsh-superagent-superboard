defmodule AgentBoard.AgentTools do
  @moduledoc """
  What each executor has installed on this machine: skills, plugins and MCP
  servers, read from the executor's own files under the home directory.

    * Claude Code: `~/.claude/skills`, `~/.claude/plugins/installed_plugins.json`
      with `enabledPlugins` of `~/.claude/settings.json`, and `mcpServers` of
      `~/.claude.json`;
    * Codex: `~/.codex/skills` and the `[plugins.*]` and `[mcp_servers.*]`
      sections of `~/.codex/config.toml`;
    * the DeepSeek agent: `~/.dsh/skills`. Where it keeps plugins and MCP
      servers is not known to the board, so those lists are `:unread`, never
      empty.

  Names only. A server's arguments, environment and headers can hold keys and
  never enter the result; a command is reduced to its file name and a URL to
  its host. A file that is absent means nothing is installed (`[]`); a file
  that cannot be read or parsed is `:unread`. A skill installed as a link that
  points nowhere is listed with `ok?: false`.

  Read on demand (Settings → AI and setup); nothing is cached or stored.
  """

  @type skill :: %{name: String.t(), description: String.t() | nil, ok?: boolean()}
  @type plugin :: %{name: String.t(), enabled?: boolean()}
  @type server :: %{name: String.t(), transport: String.t(), target: String.t() | nil}
  @type executor :: %{
          id: String.t(),
          name: String.t(),
          skills: [skill()] | :unread,
          plugins: [plugin()] | :unread,
          mcp: [server()] | :unread
        }

  @description_limit 180

  @doc "One entry per executor, in the board's order."
  @spec inventory(String.t()) :: [executor()]
  def inventory(home \\ home()) do
    codex = read(Path.join(home, ".codex/config.toml"))

    [
      %{
        id: "claude_code",
        name: "Claude Code",
        skills: skills(Path.join(home, ".claude/skills")),
        plugins: claude_plugins(home),
        mcp: claude_mcp(home)
      },
      %{
        id: "codex",
        name: "Codex",
        skills: skills(Path.join(home, ".codex/skills")),
        plugins: codex_sections(codex, "plugins", &codex_plugin/2),
        mcp: codex_sections(codex, "mcp_servers", &codex_server/2)
      },
      %{
        id: "dsh",
        name: "DeepSeek",
        skills: skills(Path.join(home, ".dsh/skills")),
        plugins: :unread,
        mcp: :unread
      }
    ]
  end

  defp home, do: Application.get_env(:agent_board, :agent_tools_home) || System.user_home!()

  # {:ok, text} | :absent | :unread
  defp read(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, :enoent} -> :absent
      {:error, _reason} -> :unread
    end
  end

  # A folder with a SKILL.md is a skill. One without it is a container (Claude
  # Code keeps the skills synced from claude.ai two levels down) and is looked
  # into, to a fixed depth. A link that points nowhere is a skill that is gone.
  @skill_depth 2

  defp skills(dir) do
    case File.ls(dir) do
      {:ok, entries} -> entries |> find_skills(dir, @skill_depth) |> Enum.sort_by(& &1.name)
      {:error, :enoent} -> []
      {:error, _reason} -> :unread
    end
  end

  defp find_skills(entries, dir, depth) do
    entries
    |> Enum.reject(&String.starts_with?(&1, "."))
    |> Enum.flat_map(fn name ->
      path = Path.join(dir, name)

      case File.read(Path.join(path, "SKILL.md")) do
        {:ok, text} -> [%{name: name, description: description(text), ok?: true}]
        {:error, _reason} -> without_skill_file(path, name, depth)
      end
    end)
  end

  defp without_skill_file(path, name, depth) do
    case {File.ls(path), dangling_link?(path)} do
      {_, true} -> [%{name: name, description: nil, ok?: false}]
      {{:ok, entries}, _} when depth > 0 -> find_skills(entries, path, depth - 1)
      _ -> []
    end
  end

  defp dangling_link?(path),
    do: match?({:ok, %{type: :symlink}}, File.lstat(path)) and not File.exists?(path)

  # The `description:` of the front matter, folded or on one line.
  defp description(text) do
    with [_, front] <- Regex.run(~r/\A---[ \t]*\r?\n(.*?)\r?\n---/s, text),
         [_, value] <- Regex.run(~r/^description:[ \t]*(.*(?:\r?\n[ \t]+.*)*)/m, front) do
      value
      |> String.replace(~r/\A[>|][+-]?[ \t]*/, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> String.trim("\"")
      |> String.trim("'")
      |> clip()
    else
      _ -> nil
    end
  end

  defp clip(""), do: nil

  defp clip(text) do
    if String.length(text) > @description_limit,
      do: String.slice(text, 0, @description_limit - 1) <> "…",
      else: text
  end

  defp claude_plugins(home) do
    with {:ok, installed} <- json(Path.join(home, ".claude/plugins/installed_plugins.json")),
         {:ok, settings} <- json(Path.join(home, ".claude/settings.json")) do
      enabled = map(settings["enabledPlugins"])

      installed["plugins"]
      |> map()
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(&%{name: &1, enabled?: enabled[&1] == true})
    end
  end

  defp claude_mcp(home) do
    with {:ok, config} <- json(Path.join(home, ".claude.json")) do
      config["mcpServers"]
      |> map()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {name, server} ->
        server = map(server)

        %{
          name: name,
          transport: if(is_binary(server["type"]), do: server["type"], else: "stdio"),
          target: target(server["command"], server["url"])
        }
      end)
    end
  end

  # {:ok, map} | [] (absent: nothing installed) | :unread
  defp json(path) do
    case read(path) do
      {:ok, text} ->
        case Jason.decode(text) do
          {:ok, %{} = data} -> {:ok, data}
          _ -> :unread
        end

      :absent ->
        {:ok, %{}}

      :unread ->
        :unread
    end
  end

  defp map(%{} = value), do: value
  defp map(_value), do: %{}

  defp target(_command, url) when is_binary(url), do: URI.parse(url).host
  defp target(command, _url) when is_binary(command), do: Path.basename(command)
  defp target(_command, _url), do: nil

  # The tables `[<table>.<name>]` of Codex's config with the keys under each,
  # read line by line: the board has no TOML parser, and only three plain
  # string or boolean keys matter. Nested tables (`.env`) are skipped whole.
  defp codex_sections(:absent, _table, _build), do: []
  defp codex_sections(:unread, _table, _build), do: :unread

  defp codex_sections({:ok, text}, table, build) do
    header = ~r/^\[#{table}\.(?:"([^"]+)"|([^.\]"]+))\]\s*$/

    {done, current} =
      text
      |> String.split(~r/\r?\n/)
      |> Enum.reduce({[], nil}, fn line, {done, current} ->
        cond do
          match = Regex.run(header, line) ->
            name = Enum.find(tl(match), &(&1 != ""))
            {close(done, current), {name, %{}}}

          String.starts_with?(String.trim_leading(line), "[") ->
            {close(done, current), nil}

          current ->
            {done, put_key(current, line)}

          true ->
            {done, nil}
        end
      end)

    done
    |> close(current)
    |> Enum.map(fn {name, keys} -> build.(name, keys) end)
    |> Enum.sort_by(& &1.name)
  end

  defp close(done, nil), do: done
  defp close(done, current), do: [current | done]

  defp put_key({name, keys}, line) do
    case Regex.run(
           ~r/^\s*(command|url|enabled)\s*=\s*(?:"([^"]*)"|(true|false))\s*(?:#.*)?$/,
           line
         ) do
      [_, key, text] -> {name, Map.put(keys, key, text)}
      [_, key, "", bool] -> {name, Map.put(keys, key, bool == "true")}
      _ -> {name, keys}
    end
  end

  defp codex_plugin(name, keys), do: %{name: name, enabled?: keys["enabled"] != false}

  defp codex_server(name, keys) do
    %{
      name: name,
      transport: if(is_binary(keys["url"]), do: "http", else: "stdio"),
      target: target(keys["command"], keys["url"])
    }
  end
end
