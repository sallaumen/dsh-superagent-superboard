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

    assert Enum.map(rows, & &1.class) == [:base, :work, :work, :work, :work, :board_ai, :voice]
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
