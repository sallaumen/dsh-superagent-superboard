defmodule AgentBoard.TitlesRequestTest do
  @moduledoc "The issue title derived from a free-text request."
  use ExUnit.Case, async: true

  alias AgentBoard.Titles

  test "a short first line is the title as written" do
    assert Titles.from_request("Corrigir o contador\nEle soma duas vezes.") ==
             "Corrigir o contador"
  end

  test "leading blank lines and a markdown heading are skipped" do
    assert Titles.from_request("\n\n## Corrigir o contador\n") == "Corrigir o contador"
  end

  test "a paragraph is cut at a clause boundary, not mid-word" do
    text =
      "Faz, em vez da gente ter formas geométricas como inimigos, meu personagem também faz, e faz tudo otenível. Uma coisa mais estilosa."

    assert Titles.from_request(text) ==
             "Faz, em vez da gente ter formas geométricas como inimigos…"
  end

  test "a sentence boundary wins over a clause boundary" do
    text =
      "O board está lento no carregamento inicial. Depois disso, tudo fica normal e sem erro algum."

    assert Titles.from_request(text) == "O board está lento no carregamento inicial…"
  end

  test "a long line without punctuation is cut at a word" do
    text = String.duplicate("palavra ", 20)
    title = Titles.from_request(text)
    assert String.ends_with?(title, "…")
    assert String.length(title) <= 73
    refute title =~ "palavr…"
  end

  test "nothing to say is an empty title" do
    assert Titles.from_request("") == ""
    assert Titles.from_request(nil) == ""
    assert Titles.from_request("   \n  ") == ""
  end
end
