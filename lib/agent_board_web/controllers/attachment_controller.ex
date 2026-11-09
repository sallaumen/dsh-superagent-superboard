defmodule AgentBoardWeb.AttachmentController do
  @moduledoc """
  A task's image, read from its repository's attachments branch.

  The page cannot fetch from a private repository, so the board does it with
  its token, but only a raster image at a path the board could have written.
  HTML and SVG can carry scripts: they stay on GitHub, reached by a redirect.
  """
  use AgentBoardWeb, :controller

  alias AgentBoard.{Board, GitHub}
  alias AgentBoard.Board.Attachments

  def show(conn, %{"repo_id" => repo_id, "hash" => hash, "name" => name}) do
    with number when is_integer(number) <- GitHub.number(repo_id),
         true <- Attachments.valid_path?(hash, name),
         %{} = repository <- Board.repository(number) do
      serve(conn, repository, hash, name)
    else
      _not_an_attachment -> send_resp(conn, 404, "")
    end
  end

  defp serve(conn, repository, hash, name) do
    if Attachments.image?(name),
      do: image(conn, repository, hash, name),
      else: redirect(conn, external: Attachments.blob_url(repository, hash, name))
  end

  defp image(conn, repository, hash, name) do
    case Attachments.read(repository, "#{hash}/#{name}", GitHub.client()) do
      {:ok, content} ->
        conn
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
        |> send_image(Attachments.image_kind(name), content)

      :error ->
        send_resp(conn, 404, "")
    end
  end

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
