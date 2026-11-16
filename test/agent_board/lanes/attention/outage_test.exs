defmodule AgentBoard.Lanes.Attention.OutageTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Attention.Outage
  alias AgentBoard.Superagents.Superagent

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "no waiting tasks or observed agent produces the neutral outage explanation" do
    card = Outage.card(0, nil)

    assert %{key: "agent-down", kind: :agent_down, waiting: 0, is_new: false, age_seconds: nil} =
             card

    assert card.why == "**The orchestrator is not responding.** Nothing moves until it is back."
    assert card.actions == [%{label: "Restart the agent", restart_agent: true, superagent: nil}]
  end

  test "the waiting count controls the sentence and the restart retains the supplied repository agent" do
    agent = %Superagent{id: 7, repository_id: 12}

    for {count, words} <- [{1, "1 task waits"}, {3, "3 tasks wait"}] do
      card = Outage.card(count, agent)
      assert card.waiting == count

      assert card.why ==
               "**The orchestrator is not responding.** #{words} for it to come back; network failures are retried on their own."

      assert [%{restart_agent: true, superagent: ^agent}] = card.actions
    end
  end
end
