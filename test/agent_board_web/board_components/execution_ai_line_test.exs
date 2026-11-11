defmodule AgentBoardWeb.BoardComponents.ExecutionAiLineTest do
  @moduledoc "Execution names the provider that answers the board's own calls."
  use ExUnit.Case, async: true

  alias AgentBoardWeb.BoardComponents.Settings.Execution

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "the line names the provider that answers and the fallbacks, never a fixed model" do
    assert Execution.ai_line(%{
             provider: :gemini,
             model: "gemini-2.5-flash",
             fallbacks: [:openai]
           }) =~
             "The board uses Gemini (gemini-2.5-flash) to answer, suggest unblocks and speak; OpenAI if it fails."

    assert Execution.ai_line(%{provider: :deepseek, model: "deepseek-flash", fallbacks: []}) =~
             "The board uses DeepSeek (deepseek-flash)"

    assert Execution.ai_line(%{provider: :rehearsal, model: nil, fallbacks: []}) =~ "rehearsal"
    assert Execution.ai_line(%{provider: nil, model: nil, fallbacks: []}) =~ "No AI key"
  end
end
