defmodule AgentBoardWeb.Components.VersionBadgeTest do
  @moduledoc "The persistent main-moved warning, without opening Settings."
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.Components.VersionBadge

  test "shows the commit count and opens Settings" do
    html =
      render_component(&VersionBadge.version_badge/1, %{
        version: %{state: :behind, behind: 2}
      })

    assert html =~ "main avançou: 2 commits"
    assert html =~ ~s(phx-click="show_panel")
    assert html =~ ~s(phx-value-panel="settings")
    assert html =~ ~s(id="version-behind")
  end

  test "uses the singular for one commit" do
    html =
      render_component(&VersionBadge.version_badge/1, %{
        version: %{state: :behind, behind: 1}
      })

    assert html =~ "main avançou: 1 commit"
    refute html =~ "main avançou: 1 commits"
  end

  test "does not render when the board is up to date or unknown" do
    for version <- [%{state: :up_to_date, behind: 0}, %{state: :unknown, behind: nil}] do
      html = render_component(&VersionBadge.version_badge/1, %{version: version})
      refute html =~ "version-behind"
    end
  end
end
