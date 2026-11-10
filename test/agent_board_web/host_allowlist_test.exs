defmodule AgentBoardWeb.HostAllowlistTest do
  @moduledoc """
  The board has no login and trusts a same-origin request. With DNS
  rebinding a page at http://evil.example:4099 resolves to 127.0.0.1 and its
  requests become same-origin, so the board answers only to the hosts it is
  reached by on this machine (and the endpoint's configured host).
  """
  use AgentBoardWeb.ConnCase, async: true

  defp with_host(conn, host), do: %{conn | host: host}

  for host <- ["evil.example", "localhost.evil.example", "127.0.0.1.evil.example"] do
    test "a request for #{host} is refused before the router", %{conn: conn} do
      refused =
        conn
        |> with_host(unquote(host))
        |> put_req_header("sec-fetch-site", "same-origin")
        |> post("/api/repos", %{owner: "attacker", name: "repo"})

      assert refused.status == 403
      assert AgentBoard.Board.repository_by_slug("attacker/repo") == nil
    end
  end

  for host <- ["localhost", "127.0.0.1", "[::1]", "board.localhost"] do
    test "a request for #{host} reaches the board", %{conn: conn} do
      assert conn |> with_host(unquote(host)) |> get("/api/repos") |> json_response(200)
    end
  end
end
