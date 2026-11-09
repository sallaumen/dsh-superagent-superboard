defmodule AgentBoardWeb.LocaleController do
  use AgentBoardWeb, :controller

  alias AgentBoardWeb.Locale

  def update(conn, %{"locale" => locale} = params) do
    if Locale.valid?(locale) do
      conn
      |> Locale.put(locale)
      |> redirect(to: Locale.safe_return_to(params["return_to"]))
    else
      send_resp(conn, :bad_request, "Unsupported language")
    end
  end

  def update(conn, _params), do: send_resp(conn, :bad_request, "Unsupported language")
end
