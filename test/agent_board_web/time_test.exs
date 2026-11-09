defmodule AgentBoardWeb.TimeTest do
  use ExUnit.Case, async: true

  alias AgentBoardWeb.Time

  test "relative and date labels follow the viewer locale" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    assert Time.ago(125) == "2 min ago"
    assert Time.day_label(~D[2026-11-08], ~D[2026-11-09]) == "Yesterday, 8 Nov"

    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
    assert Time.ago(125) == "há 2 min"
    assert Time.day_label(~D[2026-11-08], ~D[2026-11-09]) == "Ontem, 8 nov"
  end
end
