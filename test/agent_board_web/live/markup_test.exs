defmodule AgentBoardWeb.BoardComponents.MarkupTest do
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.BoardComponents.Markup

  test "keeps the inline subset and escapes everything else" do
    html = render_component(&Markup.markup/1, text: "veja **forte** e `<code>` <script>")

    assert html =~ "<strong>forte</strong>"
    assert html =~ "<code>&lt;code&gt;</code>"
    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
  end

  test "keeps the parts in the order they were written" do
    html = render_component(&Markup.markup/1, text: "veja **forte** e `código` aqui")

    assert html =~
             "<span>veja </span><strong>forte</strong><span> e </span><code>código</code><span> aqui</span>"
  end

  test "links only where asked, only http and https, never the closing punctuation" do
    text =
      "leia [o guia](https://a.test/x?y=1), https://b.test/z. e javascript:alert(1) ![foto](https://c.test/f.png)"

    html = render_component(&Markup.markup/1, text: text, links: true)

    assert html =~
             ~s(<a href="https://a.test/x?y=1" target="_blank" rel="noopener noreferrer">o guia</a>)

    assert html =~
             ~s(<a href="https://b.test/z" target="_blank" rel="noopener noreferrer">https://b.test/z</a><span>. e javascript:alert\(1\) </span>)

    assert html =~ ~s(rel="noopener noreferrer">foto</a>)
    refute html =~ "<img"
    refute html =~ ~s(href="javascript)

    refute render_component(&Markup.markup/1, text: text) =~ "<a "
  end

  test "a stored file's address reads as the file's name" do
    href = "https://github.com/o/r/blob/board-attachments/#{String.duplicate("e", 64)}/tela.png"
    html = render_component(&Markup.markup/1, text: "veja #{href}", links: true)

    assert html =~ ~s(<a href="#{href}" target="_blank" rel="noopener noreferrer">tela.png</a>)
  end

  test "an address inside code stays code" do
    html = render_component(&Markup.markup/1, text: "`https://a.test`", links: true)

    assert html =~ "<code>https://a.test</code>"
    refute html =~ "<a "
  end

  test "does not add template whitespace before the text" do
    html = render_component(&Markup.markup/1, text: "sem espaço")

    assert html =~ ">sem espaço</span>"
    refute html =~ ">\n"
  end
end
