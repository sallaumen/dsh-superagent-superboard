defmodule AgentBoardWeb.BoardComponents.MergeLogTest do
  use ExUnit.Case, async: true

  alias AgentBoardWeb.BoardComponents.MergeLog

  test "the delivered count agrees with its number in both languages" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
    assert MergeLog.delivered(0, 0) == "nenhuma issue entregue"
    assert MergeLog.delivered(1, 1) == "1 issue entregue"
    assert MergeLog.delivered(97, "≥97") == "≥97 issues entregues"

    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    assert MergeLog.delivered(0, 0) == "no issues delivered"
    assert MergeLog.delivered(1, 1) == "1 issue delivered"
    assert MergeLog.delivered(2, 2) == "2 issues delivered"
  end
end
