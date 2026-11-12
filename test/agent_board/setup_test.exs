defmodule AgentBoard.SetupTest do
  @moduledoc "What the board needs, in order, and whether each part holds."
  use ExUnit.Case, async: true

  alias AgentBoard.Setup

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  # Everything set and answering: each reader below stands for one source.
  defp ready(overrides \\ []) do
    Keyword.merge(
      [
        github: fn -> {:ok, "octo"} end,
        repositories: fn -> ["sallaumen/arena-rogue"] end,
        agents: fn ->
          [%{repository: "sallaumen/arena-rogue", model: "deepseek-flash", answer: :ok}]
        end,
        cli: fn _executor -> :ok end,
        board_ai: fn -> %{provider: :deepseek, model: "deepseek-flash", fallbacks: [:gemini]} end,
        provider_check: fn :deepseek -> :ok end,
        voice: fn -> {:ok, %{used: 10, limit: 100}} end
      ],
      overrides
    )
  end

  defp row(rows, id), do: Enum.find(rows, &(&1.id == id))

  test "the rows come in order of what depends on what, in three classes" do
    rows = Setup.verify(ready())

    assert Enum.map(rows, & &1.id) == [
             :github,
             :projects,
             :deepseek_agents,
             :claude,
             :codex,
             :board_ai,
             :voice
           ]

    assert Enum.map(rows, & &1.class) == [:work, :work, :work, :work, :work, :board_ai, :voice]
    assert Enum.all?(rows, &(&1.state == :ok))
    assert Setup.next_step(rows) == nil
  end

  test "an expired GitHub token fails and is the next step" do
    rows = Setup.verify(ready(github: fn -> {:error, {:http, 401}} end))

    assert %{state: :failed, fix: %{href: "https://github.com/settings/tokens"}} =
             row(rows, :github)

    assert %{id: :github} = Setup.next_step(rows)
  end

  test "without a key the board's own AI is missing, and without ElevenLabs the voice is the browser's" do
    rows =
      Setup.verify(
        ready(
          board_ai: fn -> %{provider: nil, model: nil, fallbacks: []} end,
          voice: fn -> {:error, :not_configured} end
        )
      )

    assert %{state: :missing, fix: %{href: "https://platform.deepseek.com/api_keys"}} =
             row(rows, :board_ai)

    assert %{state: :off} = row(rows, :voice)
    assert %{id: :board_ai} = Setup.next_step(rows)
  end

  test "a key the provider refuses fails, and the reason names the provider" do
    rows = Setup.verify(ready(provider_check: fn :deepseek -> {:error, {:http, 401}} end))

    assert %{state: :failed, detail: detail} = row(rows, :board_ai)
    assert detail =~ "DeepSeek"
  end

  test "a CLI that is installed but logged out says the command that fixes it" do
    rows =
      Setup.verify(
        ready(
          cli: fn
            "codex" -> {:error, :logged_out}
            _ -> :ok
          end
        )
      )

    assert %{state: :failed, fix: %{command: "codex login"}} = row(rows, :codex)
    # Claude Code and Codex are optional: a logged-out Codex is not the next step.
    assert Setup.next_step(rows) == nil
  end

  test "an agent that does not answer fails its row, with how many answered" do
    rows =
      Setup.verify(
        ready(
          agents: fn ->
            [
              %{repository: "sallaumen/arena-rogue", model: "deepseek-flash", answer: :ok},
              %{
                repository: "sallaumen/o_colmex",
                model: "deepseek-flash",
                answer: {:error, :econnrefused}
              }
            ]
          end
        )
      )

    assert %{state: :failed, detail: detail} = row(rows, :deepseek_agents)
    assert detail =~ "1 of 2"
    assert detail =~ "sallaumen/o_colmex"
  end

  describe "a board with no agent yet" do
    # No agent: the rows of a first one show, each from its own reader.
    defp first(overrides) do
      ready(
        Keyword.merge(
          [
            agents: fn -> [] end,
            waiting: fn -> 0 end,
            agent_tools: fn -> [{"node", :ok}, {"tmux", :ok}, {"gh", :ok}] end,
            agent_bot: fn -> {:ok, "octo-agent"} end
          ],
          overrides
        )
      )
    end

    test "says what a first agent needs, after the agents row and before the executors" do
      rows = Setup.verify(first([]))

      assert [:github, :projects, :deepseek_agents, :agent_tools, :agent_bot, :claude | _rest] =
               Enum.map(rows, & &1.id)

      assert %{state: :ok, detail: "node, tmux, gh are on this machine.", fix: nil} =
               row(rows, :agent_tools)

      assert %{state: :ok, detail: "Signed in as octo-agent.", required: false} =
               row(rows, :agent_bot)

      # Optional parts: nothing here is the board's next step.
      assert Setup.next_step(rows) == nil
    end

    test "a missing or old tool names itself and the command that installs it" do
      rows =
        Setup.verify(
          first(
            agent_tools: fn ->
              [{"node", {:old, "20.11.0", "22.19.0"}}, {"tmux", :missing}, {"python3", :missing}]
            end
          )
        )

      # Optional and not there yet: off, so a check on a board without DeepSeek passes.
      assert %{state: :off, detail: detail, fix: %{command: command}} =
               row(rows, :agent_tools)

      assert detail =~ "Not on this machine: tmux, python3."
      assert detail =~ "node 20.11.0 is older than the 22.19.0 the agent needs."
      assert command == "brew install tmux python node"
    end

    test "an agent signed in as the owner fails: it needs an account of its own" do
      rows = Setup.verify(first(agent_bot: fn -> {:ok, "octo"} end))

      assert %{state: :failed, detail: detail, fix: %{command: command}} = row(rows, :agent_bot)
      assert detail =~ "signed in as octo, your own account"
      assert command =~ "GH_CONFIG_DIR=~/.config/gh-agent gh auth login"
    end

    test "no sign-in for the agent is off, with the command, in both readings" do
      live = Setup.verify(first(agent_bot: fn -> {:error, :missing} end))
      assert %{state: :off, fix: %{command: _}} = row(live, :agent_bot)

      # The configuration reading asks each source whether it is set, not who answers.
      set = [github: fn -> true end, cli: fn _ -> true end, voice: fn -> true end]

      config = Setup.checklist(first(set ++ [agent_bot: fn -> false end]))
      assert %{state: :off} = row(config, :agent_bot)

      present = Setup.checklist(first(set ++ [agent_bot: fn -> true end]))
      assert %{state: :configured} = row(present, :agent_bot)
      assert %{state: :configured} = row(present, :agent_tools)
    end

    test "an agent installed outside the board sends the owner to Projects to add it" do
      rows = Setup.verify(first(waiting: fn -> 1 end))

      assert %{
               state: :off,
               detail: detail,
               fix: %{section: "projects", label: "Add it in Projects"}
             } =
               row(rows, :deepseek_agents)

      assert detail =~ "1 agent is installed on this machine"
    end

    test "a board that has an agent shows none of this" do
      rows = Setup.verify(ready())

      refute row(rows, :agent_tools)
      refute row(rows, :agent_bot)
    end
  end

  test "no project yet is the next step, and its fix opens Projects" do
    rows = Setup.verify(ready(repositories: fn -> [] end, agents: fn -> [] end))

    assert %{state: :missing, fix: %{section: "projects"}} = row(rows, :projects)
    assert %{id: :projects} = Setup.next_step(rows)
  end

  test "the checklist without a click reads configuration only: present is configured, not ok" do
    rows =
      Setup.checklist(
        github: fn -> true end,
        repositories: fn -> ["sallaumen/arena-rogue"] end,
        agents: fn -> [%{repository: "sallaumen/arena-rogue", model: "deepseek-flash"}] end,
        cli: fn _executor -> true end,
        board_ai: fn -> %{provider: :deepseek, model: "deepseek-flash", fallbacks: []} end,
        voice: fn -> false end
      )

    assert %{state: :configured} = row(rows, :github)
    assert %{state: :configured} = row(rows, :board_ai)
    assert %{state: :off} = row(rows, :voice)
    assert Setup.next_step(rows) == nil
  end
end
