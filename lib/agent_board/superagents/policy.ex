defmodule AgentBoard.Superagents.Policy do
  @moduledoc """
  The agent's instructions, kept the same for every agent of every board.

  Each `dsh-superagent` holds three sections of text that are its policy:
  Communication, Ticket scope and Delivery requirements. The official text is
  the three files in `docs/agent/prompts/`, compiled into this module, so it
  reaches a board with an update. A project may add rules of its own: extra
  lines per section, kept in the board's settings
  (`agent_policy_rules:<profile>`). What an agent should hold is the policy's
  lines followed by its project's rules.

  Nothing is applied by itself. `compare/2` says how an agent's text differs,
  line by line (each line of a section is one rule); `apply/4` saves the
  desired text at the revision that was compared, so a save made in the dsh
  panel in between is a `:conflict` and never overwritten. The lines only the
  agent has are lost on apply unless the owner keeps them as project rules.
  The other keys of the agent's prompt config (its skills) travel unchanged.

  What the board last saw per agent is kept in memory for the Attention bell
  (`differing/0`): read at boot, when a project's controls open and after an
  apply. An agent that does not answer is unknown, never "differs".
  """

  alias AgentBoard.{Settings, Superagents}
  alias AgentBoard.Superagents.{Manager, Superagent}

  @sections ~w(communication scope delivery)
  @dir Path.expand("../../../docs/agent/prompts", __DIR__)

  for section <- @sections do
    @external_resource Path.join(@dir, section <> ".md")
  end

  # A file is the section's text plus one newline (`scripts/agent/prompts.sh`).
  @base Map.new(@sections, fn section ->
          {section,
           @dir |> Path.join(section <> ".md") |> File.read!() |> String.trim_trailing("\n")}
        end)

  @key {__MODULE__, :seen}

  @type line :: %{id: String.t(), text: String.t()}
  @type section :: %{
          name: String.t(),
          current?: boolean(),
          missing: non_neg_integer(),
          own: [line()],
          rules: [line()]
        }
  @type comparison :: %{revision: integer(), current?: boolean(), sections: [section()]}

  @doc "The section names, in the agent's order."
  def sections, do: @sections

  @doc "The official text of each section."
  @spec base() :: %{String.t() => String.t()}
  def base, do: @base

  @doc "A project's own rules: lines per section, none by default."
  @spec rules(Superagent.t()) :: %{String.t() => [String.t()]}
  def rules(%Superagent{} = superagent) do
    with value when is_binary(value) <- Settings.get(rules_key(superagent)),
         {:ok, %{} = stored} <- Jason.decode(value) do
      Map.new(@sections, fn section ->
        {section, stored |> Map.get(section, []) |> List.wrap() |> Enum.filter(&is_binary/1)}
      end)
    else
      _ -> Map.new(@sections, &{&1, []})
    end
  end

  defp rules_key(%Superagent{profile: profile}), do: "agent_policy_rules:#{profile}"

  @doc "What the agent should hold: the policy, then the project's rules."
  @spec desired(%{String.t() => [String.t()]}) :: %{String.t() => String.t()}
  def desired(rules) do
    Map.new(@sections, fn section ->
      {section, Enum.join([@base[section] | Map.get(rules, section, [])], "\n")}
    end)
  end

  @doc """
  How the agent's active text differs from what it should hold. Per section:
  how many of the policy's lines it lacks, the lines only it has, and the
  project's stored rules. Remembers the answer for the bell.
  """
  @spec compare(Superagent.t(), module()) :: {:ok, comparison()} | {:error, term()}
  def compare(%Superagent{} = superagent, manager \\ Manager.impl()) do
    case manager.prompts(superagent) do
      {:ok, %{revision: revision, config: config}} ->
        {:ok, comparison(superagent, revision, config)}

      {:error, reason} ->
        remember(superagent, :unknown)
        {:error, reason}
    end
  end

  defp comparison(superagent, revision, config) do
    rules = rules(superagent)
    desired = desired(rules)

    sections =
      Enum.map(@sections, fn name ->
        active = text(config[name])
        wanted = lines(desired[name])
        held = lines(active)

        %{
          name: name,
          current?: active == desired[name],
          missing: Enum.count(wanted, &(&1 not in held)),
          own: held |> Enum.reject(&(&1 in wanted)) |> Enum.map(&line/1),
          rules: Enum.map(rules[name], &line/1)
        }
      end)

    current? = Enum.all?(sections, & &1.current?)
    remember(superagent, current?)
    %{revision: revision, current?: current?, sections: sections}
  end

  @doc """
  Saves the policy on the agent. `keep` names, by id, the lines to hold as
  this project's rules, among its stored rules and the lines only the agent
  has; every other agent-only line is replaced. `{:error, :conflict}` when the
  agent's text changed since it was read: compare again.
  """
  @spec apply(Superagent.t(), [String.t()], module(), String.t()) ::
          {:ok, integer()} | {:error, term()}
  def apply(%Superagent{} = superagent, keep, manager \\ Manager.impl(), actor \\ "owner")
      when is_list(keep) do
    with {:ok, %{revision: revision, config: config}} <- manager.prompts(superagent) do
      rules =
        Map.new(comparison(superagent, revision, config).sections, fn section ->
          {section.name,
           for(line <- section.rules ++ section.own, line.id in keep, do: line.text)}
        end)

      case manager.save_prompts(superagent, Map.merge(config, desired(rules)), revision) do
        {:ok, saved} ->
          :ok = Settings.put(rules_key(superagent), encode(rules))
          remember(superagent, true)
          Superagents.event(superagent, "policy_applied", nil, nil, actor, "revision #{saved}")
          {:ok, saved}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # No rule at all removes the setting instead of storing empty lists.
  defp encode(rules) do
    if Enum.all?(rules, fn {_section, lines} -> lines == [] end),
      do: nil,
      else: Jason.encode!(rules)
  end

  @doc "Compares every agent once, for the bell: at boot, after a board update."
  @spec refresh_all(module()) :: :ok
  def refresh_all(manager \\ Manager.impl()) do
    Enum.each(Superagents.list(), &compare(&1, manager))
  end

  @doc "The ids of the agents last seen holding a text other than the policy."
  @spec differing() :: [integer()]
  def differing do
    for {id, false} <- :persistent_term.get(@key, %{}), do: id
  end

  @doc false
  def forget, do: :persistent_term.erase(@key)

  defp remember(%Superagent{id: id}, current?) do
    seen = :persistent_term.get(@key, %{})
    if seen[id] != current?, do: :persistent_term.put(@key, Map.put(seen, id, current?))
    :ok
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""

  defp lines(text), do: text |> String.split("\n") |> Enum.reject(&(String.trim(&1) == ""))

  # The id is what a form sends back: the line itself can be thousands of
  # characters long.
  defp line(text) do
    id = :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower) |> binary_part(0, 16)
    %{id: id, text: text}
  end
end
