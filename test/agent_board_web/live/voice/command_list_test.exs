defmodule AgentBoardWeb.BoardComponents.Voice.CommandListTest do
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.Voice.Commands
  alias AgentBoardWeb.BoardComponents.Voice.CommandList

  # The tab's one language: the Gettext locale words the list, and the voice
  # language derived from it (`@voice.language`) picks what to say.
  defp list(locale, language) do
    Gettext.with_locale(AgentBoardWeb.Gettext, locale, fn ->
      render_component(&CommandList.list/1, open: true, language: language)
    end)
  end

  test "the whole list, what to say included, is in the tab's language" do
    english = list("en", "en-US")
    assert english =~ "The agent&#39;s runs"
    assert english =~ "each run, for how long and its last report"
    assert english =~ "asks for your yes"
    assert english =~ "What is running now?"
    assert english =~ ~s(phx-value-text="What is failing?")
    refute english =~ "O que está rodando agora?"
    refute english =~ "Execuções do agente"
    refute english =~ "só lê"

    portuguese = list("pt_BR", "pt-BR")
    assert portuguese =~ "Execuções do agente"
    assert portuguese =~ "cada execução, há quanto tempo e o último relato"
    assert portuguese =~ "pede seu sim"
    assert portuguese =~ "O que está rodando agora?"
  end

  test "every command says something in each language, and the two differ" do
    pairs = Enum.zip(Commands.items("pt-BR"), Commands.items("en-US"))
    assert length(pairs) == 24

    for {portuguese, english} <- pairs do
      assert portuguese.say != "" and english.say != ""
      assert portuguese.say != english.say or portuguese.say == "Status"
      # a ready-to-send example never carries a number to fill in, in either language
      if english.try, do: refute(english.say =~ ~r/\d/)
    end
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
