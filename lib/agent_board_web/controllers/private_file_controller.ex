defmodule AgentBoardWeb.PrivateFileController do
  @moduledoc """
  A raster image from a task's private context, for the board's own page.

  The folder name, the path and the image kind are checked by
  `AgentBoard.Board.PrivateContext.image/3`: a plain path under the folder, a
  regular file reached without a link, PNG, JPEG, WebP or GIF. Anything else,
  the note included, is a 404. The route is same-origin only (the router's
  `refuse_cross_site`), so another site cannot read it through an `<img>`.
  """
  use AgentBoardWeb, :controller

  alias AgentBoard.{Board, GitHub}
  alias AgentBoard.Board.PrivateContext

  def show(conn, %{"repo_id" => repo_id, "dir" => dir, "path" => [_ | _] = segments}) do
    with number when is_integer(number) <- GitHub.number(repo_id),
         %{} = repository <- Board.repository(number),
         {:ok, content, kind} <- PrivateContext.image(repository, dir, Path.join(segments)) do
      conn
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", "private, no-store")
      |> send_image(kind, content)
    else
      _not_a_private_image -> send_resp(conn, 404, "")
    end
  end

  def show(conn, _no_file), do: send_resp(conn, 404, "")

  # One literal type per kind: no value from the request names what is served.
  defp send_image(conn, :png, content),
    do: conn |> put_resp_content_type("image/png", nil) |> send_resp(200, content)

  defp send_image(conn, :jpeg, content),
    do: conn |> put_resp_content_type("image/jpeg", nil) |> send_resp(200, content)

  defp send_image(conn, :webp, content),
    do: conn |> put_resp_content_type("image/webp", nil) |> send_resp(200, content)

  defp send_image(conn, :gif, content),
    do: conn |> put_resp_content_type("image/gif", nil) |> send_resp(200, content)
end
