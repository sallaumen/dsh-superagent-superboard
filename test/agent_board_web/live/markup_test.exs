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

  test "does not add template whitespace before the text" do
    html = render_component(&Markup.markup/1, text: "sem espaço")

    assert html =~ ">sem espaço</span>"
    refute html =~ ">\n"
  end
end
