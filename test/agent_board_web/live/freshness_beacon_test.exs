defmodule AgentBoardWeb.BoardComponents.FreshnessBeaconTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.BoardComponents.FreshnessBeacon

  test "every time in the popover is on the same clock as the chip" do
    at = ~U[2026-11-09 14:11:00Z]

    freshness = %{
      state: :offline,
      at: at,
      age_sec: 420,
      sources: [
        %{code: :github_failed, kind: :halt, attempted_at: ~U[2026-11-09 14:15:00Z]}
      ]
    }

    html = render_component(&FreshnessBeacon.beacon/1, freshness: freshness, tz_offset: 180)

    assert html =~ "11:11"
    assert html =~ "11:15"
    refute html =~ "14:11"
    refute html =~ "14:15"
  end
end
