defmodule AgentBoardWeb.Locale do
  @moduledoc """
  The board interface locale belongs to the viewer's browser.
  """

  import Plug.Conn

  @cookie "board_locale"
  @default "en"
  @supported ["en", "pt-BR"]
  @year 365 * 24 * 60 * 60

  def default, do: @default
  def supported, do: @supported

  def valid?(locale), do: locale in @supported

  def normalize(locale) when locale in @supported, do: locale
  def normalize(_), do: @default

  def gettext_locale("pt-BR"), do: "pt_BR"
  def gettext_locale(_), do: "en"

  @doc """
  The language of the sentences `AgentBoard.Actions.phrase/3` writes for this
  viewer (`"pt-BR"` or `"en-US"`), from the process's interface language.
  """
  def language do
    if Gettext.get_locale(AgentBoardWeb.Gettext) == "pt_BR", do: "pt-BR", else: "en-US"
  end

  def init(opts), do: opts
  def call(conn, opts), do: fetch(conn, opts)

  def fetch(conn, _opts) do
    conn = fetch_cookies(conn)
    locale = normalize(conn.cookies[@cookie])

    conn
    |> assign(:board_locale, locale)
    |> put_session(:board_locale, locale)
    |> set_gettext_locale(locale)
  end

  def put(conn, locale) when locale in @supported do
    put_resp_cookie(conn, @cookie, locale, max_age: @year, same_site: "Lax", http_only: true)
  end

  def on_mount(:default, _params, session, socket) do
    locale = normalize(session["board_locale"])
    Gettext.put_locale(AgentBoardWeb.Gettext, gettext_locale(locale))
    {:cont, Phoenix.Component.assign(socket, :board_locale, locale)}
  end

  def safe_return_to(path) when is_binary(path) do
    uri = URI.parse(path)

    if uri.path == "/" and uri.host == nil and uri.scheme == nil and uri.fragment == nil and
         not String.contains?(path, ["\\", "\r", "\n"]) do
      path
    else
      "/"
    end
  end

  def safe_return_to(_), do: "/"

  defp set_gettext_locale(conn, locale) do
    Gettext.put_locale(AgentBoardWeb.Gettext, gettext_locale(locale))
    conn
  end
end
