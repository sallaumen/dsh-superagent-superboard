defmodule AgentBoard.Voice.SpeakableTest do
  @moduledoc "What the voice reads: no markdown, no slugs, no hash signs."
  use ExUnit.Case, async: true

  alias AgentBoard.Voice.Speakable

  test "screen notation becomes words a listener follows" do
    assert Speakable.clean("O PR #28 de **sallaumen/arena-rogue** passou.") ==
             "O PR 28 de arena rogue passou."

    assert Speakable.clean(
             "Veja [o PR](https://github.com/x/y/pull/1) e https://example.com agora."
           ) ==
             "Veja o PR e agora."

    assert Speakable.clean("- primeiro item\n- segundo `item`") == "primeiro item segundo item"

    assert Speakable.clean("12 tarefas no arena-rogue, de 2-3 dias.") ==
             "12 tarefas no arena rogue, de 2-3 dias."
  end

  test "ordinary sentences are left alone" do
    for text <- ["Você quer e/ou precisa disso?", "A 120 km/h.", "Tudo tranquilo por aqui."] do
      assert Speakable.clean(text) == text
    end
  end
end
