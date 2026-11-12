defmodule AgentBoard.Superagents.PolicyTest do
  @moduledoc "The agent's instructions: compared with the board's policy and applied by the owner, never by themselves."
  # What the board last saw per agent lives in one global term.
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Settings, Superagents}
  alias AgentBoard.Superagents.{FakeManager, Policy}

  setup do
    {:ok, _pid} = FakeManager.start()
    Policy.forget()
    on_exit(&Policy.forget/0)

    {:ok, repo} = Board.add_repository("fixture", "policy")

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-policy",
        port: 3198,
        state_dir: "/tmp/policy-superagent"
      })

    %{superagent: superagent}
  end

  defp holds(superagent, sections, revision \\ 3) do
    config = Map.merge(%{"skills" => %{"playbook" => "kept"}}, Map.merge(Policy.base(), sections))
    FakeManager.put_prompts(superagent.id, %{revision: revision, config: config})
  end

  defp section(comparison, name), do: Enum.find(comparison.sections, &(&1.name == name))

  test "the policy is the three files, without the file's last newline" do
    assert Map.keys(Policy.base()) == ["communication", "delivery", "scope"]
    assert Policy.base()["communication"] =~ "Relatório do agente"
    refute String.ends_with?(Policy.base()["delivery"], "\n")
  end

  test "an agent holding the policy is current, and nobody is told otherwise", %{superagent: sa} do
    holds(sa, %{})

    assert {:ok, %{revision: 3, current?: true}} = Policy.compare(sa, FakeManager)
    assert Policy.differing() == []
  end

  test "a stale rule and a rule of its own are both lines only the agent has", %{superagent: sa} do
    [first | rest] = String.split(Policy.base()["delivery"], "\n")
    stale = "An older wording of the first rule."
    own = "Every UI change shows a before and an after."
    holds(sa, %{"delivery" => Enum.join([stale | rest] ++ [own], "\n")})

    assert {:ok, %{current?: false} = comparison} = Policy.compare(sa, FakeManager)
    assert %{current?: true, missing: 0, own: []} = section(comparison, "scope")

    assert %{current?: false, missing: 1, own: [%{text: ^stale}, %{text: ^own}], rules: []} =
             section(comparison, "delivery")

    refute first == stale
    assert Policy.differing() == [sa.id]
  end

  test "applying replaces what was not kept, keeps the chosen rule and the agent's other keys",
       %{superagent: sa} do
    stale = "An older wording."
    own = "Every UI change shows a before and an after."
    holds(sa, %{"delivery" => Enum.join([stale, own], "\n")})

    {:ok, comparison} = Policy.compare(sa, FakeManager)
    keep = for line <- section(comparison, "delivery").own, line.text == own, do: line.id

    assert {:ok, 4} = Policy.apply(sa, keep, FakeManager)

    assert {:ok, %{revision: 4, config: config}} = FakeManager.prompts(sa)
    assert config["delivery"] == Policy.base()["delivery"] <> "\n" <> own
    assert config["communication"] == Policy.base()["communication"]
    assert config["skills"] == %{"playbook" => "kept"}
    refute config["delivery"] =~ stale

    # The rule is the project's now: the agent is current, and the rule is
    # offered again (to drop it) the next time.
    assert Policy.rules(sa)["delivery"] == [own]
    assert {:ok, %{current?: true} = after_apply} = Policy.compare(sa, FakeManager)
    assert [%{text: ^own}] = section(after_apply, "delivery").rules
    assert Policy.differing() == []
    assert [%{action: "policy_applied", detail: "revision 4"} | _] = Superagents.events(sa)

    # Dropping it is applying without keeping it.
    assert {:ok, 5} = Policy.apply(sa, [], FakeManager)
    assert Policy.rules(sa)["delivery"] == []
    assert Settings.get("agent_policy_rules:superagent-policy") == nil
  end

  test "a save in the agent's panel in between is a conflict, not an overwrite" do
    defmodule Racing do
      @moduledoc false
      def prompts(_superagent), do: {:ok, %{revision: 3, config: %{"delivery" => "edited"}}}
      def save_prompts(_superagent, _config, 3), do: {:error, :conflict}
    end

    superagent = hd(Superagents.list())
    assert Policy.apply(superagent, [], Racing) == {:error, :conflict}
    assert Policy.rules(superagent)["delivery"] == []
  end

  test "an agent that does not answer is unknown, never listed as different", %{superagent: sa} do
    holds(sa, %{"scope" => "something else"})
    {:ok, _comparison} = Policy.compare(sa, FakeManager)
    assert Policy.differing() == [sa.id]

    FakeManager.put_prompts(sa.id, {:error, :econnrefused})
    assert Policy.compare(sa, FakeManager) == {:error, :econnrefused}
    assert Policy.differing() == []

    holds(sa, %{"scope" => "something else"})
    assert Policy.refresh_all(FakeManager) == :ok
    assert Policy.differing() == [sa.id]
  end
end
