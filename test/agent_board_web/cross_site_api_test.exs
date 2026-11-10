defmodule AgentBoardWeb.CrossSiteApiTest do
  @moduledoc """
  The API has no login: it listens on 127.0.0.1 only. A page on another site
  the owner opens can still reach localhost with a form or an `<audio src>`,
  so a request the browser marks as coming from another site is refused
  before it reaches a paid call or an action. The board's own page sends
  `same-origin`, and a script (curl) sends no such header.
  """
  use AgentBoardWeb.ConnCase, async: true

  alias AgentBoard.Board

  for site <- ["cross-site", "same-site"] do
    test "a #{site} request is refused before it acts", %{conn: conn} do
      refused =
        conn
        |> put_req_header("sec-fetch-site", unquote(site))
        |> post("/api/repos", %{owner: "attacker", name: "repo"})

      assert json_response(refused, 403) == %{"error" => "cross_site_request"}
      assert Board.repository_by_slug("attacker/repo") == nil

      speech =
        build_conn()
        |> put_req_header("sec-fetch-site", unquote(site))
        |> put_req_header("accept", "audio/mpeg")
        |> get("/api/voice/stream?text=paid")

      assert speech.status == 403
    end
  end

  test "the board's own page and a script still reach the API", %{conn: conn} do
    same_origin =
      conn
      |> put_req_header("sec-fetch-site", "same-origin")
      |> post("/api/repos", %{owner: "fixture", name: "same-origin"})

    assert json_response(same_origin, 201)

    script = post(build_conn(), "/api/repos", %{owner: "fixture", name: "script"})
    assert json_response(script, 201)
  end
end
