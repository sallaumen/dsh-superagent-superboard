defmodule AgentBoard.ConversationTest do
  @moduledoc "The conversation memory: recent turns verbatim, older ones summarized."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.AI.Engines.Scripted
  alias AgentBoard.Conversation

  setup do
    previous =
      for key <- [:ai_rehearsal, :ai_engine, :ai_api_key, :ai_script],
          into: %{},
          do: {key, Application.get_env(:agent_board, key)}

    Application.put_env(:agent_board, :ai_rehearsal, false)
    Application.put_env(:agent_board, :ai_engine, Scripted)
    Application.put_env(:agent_board, :ai_api_key, "test-key")

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:agent_board, key),
          else: Application.put_env(:agent_board, key, value)
      end
    end)
  end

  defp talk(n) do
    for i <- 1..n do
      {:ok, _} = Conversation.record(if(rem(i, 2) == 1, do: "owner", else: "agent"), "fala #{i}")
    end
  end

  test "the context keeps the recent turns in order" do
    talk(4)
    assert %{summary: nil, earlier: 0, turns: turns} = Conversation.context()
    assert Enum.map(turns, & &1.text) == ["fala 1", "fala 2", "fala 3", "fala 4"]
  end

  test "a long chat is folded into a summary and nothing is lost" do
    test_pid = self()

    Application.put_env(:agent_board, :ai_script, fn %{
                                                       name: :summarize_conversation,
                                                       prompt: prompt
                                                     } ->
      send(test_pid, {:folded, prompt})
      Scripted.answer(%{"summary" => "O dono pediu o placar; tarefa 42 criada."})
    end)

    talk(30)
    assert Conversation.context().earlier == 14

    assert {:ok, _summary} = Conversation.compact()
    assert_received {:folded, prompt}
    assert prompt =~ "fala 1"
    refute prompt =~ "fala 30"

    context = Conversation.context()
    assert context.summary == "O dono pediu o placar; tarefa 42 criada."
    assert context.earlier == 0
    assert List.last(context.turns).text == "fala 30"
    assert length(context.turns) == 16

    # Below the threshold again: nothing to fold.
    assert Conversation.compact() == :noop
  end

  test "a failed summary keeps the turns" do
    Application.put_env(:agent_board, :ai_script, fn _ -> {:error, :usage_limit} end)
    talk(30)

    assert {:error, _reason} = Conversation.compact()
    assert Conversation.context().summary == nil
    assert Conversation.context().earlier == 14
  end

  test "text is trimmed and capped" do
    {:ok, turn} = Conversation.record("owner", "  " <> String.duplicate("a", 3_000) <> "  ")
    assert String.length(turn.text) == 2_000
  end
end
