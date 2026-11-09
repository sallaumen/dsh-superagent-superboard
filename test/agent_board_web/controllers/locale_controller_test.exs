defmodule AgentBoardWeb.LocaleControllerTest do
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.Locale

  test "English is the default for an unconfigured browser", %{conn: conn} do
    conn = Plug.Test.delete_req_cookie(conn, "board_locale")
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Board language"
    assert html =~ "Settings"
    assert html =~ ~s(name="_csrf_token")
    assert get(conn, ~p"/").resp_body =~ ~s(lang="en")
  end

  test "the Portuguese choice persists in a browser cookie and does not change voice settings", %{
    conn: conn
  } do
    original_voice = AgentBoard.Voice.language()

    conn = post(conn, ~p"/language", %{"locale" => "pt-BR", "return_to" => "/?panel=settings"})

    assert redirected_to(conn) == "/?panel=settings"
    assert conn.resp_cookies["board_locale"].value == "pt-BR"

    conn = conn |> recycle() |> get(~p"/")
    assert conn.resp_body =~ ~s(lang="pt-BR")
    assert conn.resp_body =~ "Idioma do board"
    assert AgentBoard.Voice.language() == original_voice
  end

  test "invalid language is rejected and a bad return path cannot redirect off-site", %{
    conn: conn
  } do
    conn = post(conn, ~p"/language", %{"locale" => "fr"})
    assert conn.status == 400
    refute Map.has_key?(conn.resp_cookies, "board_locale")
    assert Locale.safe_return_to("//example.com") == "/"
    assert Locale.safe_return_to("https://example.com") == "/"
    assert Locale.safe_return_to("/\\example.com") == "/"
    assert Locale.safe_return_to("/?view=hoje") == "/?view=hoje"
  end

  test "an invalid or missing browser cookie falls back to English", %{conn: conn} do
    conn = conn |> Plug.Test.put_req_cookie("board_locale", "de") |> get(~p"/")
    assert conn.resp_body =~ ~s(lang="en")
    assert conn.resp_body =~ "Board language"
  end

  test "two connected browsers keep independent interface languages", %{conn: conn} do
    english_conn = Plug.Test.delete_req_cookie(conn, "board_locale")
    {:ok, english, _html} = live(english_conn, ~p"/")
    {:ok, portuguese, _html} = live(conn, ~p"/")

    assert render(english) =~ "Board language"
    assert render(portuguese) =~ "Idioma do board"
    refute render(english) =~ "Idioma do board"
  end

  test "settings and language remain available before a repository is tracked", %{conn: conn} do
    conn = Plug.Test.delete_req_cookie(conn, "board_locale")
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element(".ab-empty button", "Open Settings") |> render_click()
    assert_patch(view, "/?panel=settings")
    assert has_element?(view, "#panel-settings #board-language-form")

    response =
      post(conn, ~p"/language", %{"locale" => "pt-BR", "return_to" => "/?panel=settings"})

    assert redirected_to(response) == "/?panel=settings"

    {:ok, portuguese, _html} = live(recycle(response), "/?panel=settings")

    assert has_element?(
             portuguese,
             "#panel-settings #board-language-form button[aria-pressed=true]",
             "Português (Brasil)"
           )
  end
end
