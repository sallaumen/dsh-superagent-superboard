defmodule AgentBoardWeb.BoardComponents.VoiceCommandListTest do
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.Voice.Commands
  alias AgentBoardWeb.BoardComponents.VoiceCommandList

  defp list(locale) do
    Gettext.with_locale(AgentBoardWeb.Gettext, locale, fn ->
      render_component(&VoiceCommandList.list/1, open: true)
    end)
  end

  test "what each command does follows the interface; what to say stays in the voice's language" do
    english = list("en")
    assert english =~ "The agent&#39;s runs"
    assert english =~ "each run, for how long and its last report"
    assert english =~ "asks for your yes"
    assert english =~ "O que está rodando agora?"
    refute english =~ "Execuções do agente"
    refute english =~ "só lê"

    portuguese = list("pt_BR")
    assert portuguese =~ "Execuções do agente"
    assert portuguese =~ "cada execução, há quanto tempo e o último relato"
    assert portuguese =~ "pede seu sim"
    assert portuguese =~ "O que está rodando agora?"
  end

  test "every title and description has its Portuguese" do
    texts =
      for group <- Commands.groups(), text <- [group.title | Enum.map(group.items, & &1.does)] do
        text
      end

    for text <- texts do
      portuguese =
        Gettext.with_locale(AgentBoardWeb.Gettext, "pt_BR", fn ->
          Gettext.gettext(AgentBoardWeb.Gettext, text)
        end)

      assert portuguese != text, "no Portuguese for #{inspect(text)}"
    end
  end
end
