defmodule AgentBoardWeb.SettingsSystemTest do
  @moduledoc "Settings → System: version, the browser controls and the activity section."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  test "System holds the version card, the browser controls and the activity list", %{
    conn: conn
  } do
    {:ok, _repo} = Board.add_repository("fixture", "system")

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/system&panel=settings&section=system")

    assert has_element?(view, "#version-title")
    assert has_element?(view, "#version-check", "Verificar de novo")
    assert has_element?(view, "#settings-browser-title", "Neste navegador")
    assert has_element?(view, "#settings-theme-toggle[phx-hook=ThemeToggle]")

    assert has_element?(view, ~s(button[data-phx-theme="system"]), "Sistema")
    assert has_element?(view, ~s(button[data-phx-theme="light"]), "Claro")
    assert has_element?(view, ~s(button[data-phx-theme="dark"]), "Escuro")

    assert has_element?(
             view,
             "#board-language-form button[aria-pressed=true]",
             "Português (Brasil)"
           )

    assert has_element?(view, "#settings-activity-title", "Atividade")
    assert has_element?(view, "#settings-activity", "Últimos 20 eventos")

    view |> element(".settings-link") |> render_click()

    assert_patch(view, "/?panel=settings&repo=fixture%2Fsystem&section=voice")
    assert has_element?(view, ".settings-nav__item.is-current", "Voz e resumo")
  end
end
