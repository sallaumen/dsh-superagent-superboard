defmodule AgentBoardWeb.DevCheckOriginTest do
  @moduledoc """
  The live board runs in dev on 127.0.0.1. Browsers apply no CORS to a
  WebSocket, so a page on another site can open the board's sockets unless the
  endpoint checks the Origin: the live-reload socket streams server log lines,
  the LiveView socket drives the board. The dev config must accept the board's
  own pages on any local port and refuse every other site.
  """
  use ExUnit.Case, async: true

  import Plug.Test

  alias Phoenix.Socket.Transport

  @dev_check_origin Config.Reader.read!("config/dev.exs")
                    |> get_in([:agent_board, AgentBoardWeb.Endpoint, :check_origin])

  defp check(origin) do
    conn(:get, "/phoenix/live_reload/socket/websocket")
    |> Plug.Conn.put_req_header("origin", origin)
    |> Transport.check_origin(__MODULE__, AgentBoardWeb.Endpoint, check_origin: @dev_check_origin)
  end

  test "a socket from another site is refused" do
    refused = check("http://evil.example")

    assert refused.halted
    assert refused.status == 403
  end

  for origin <- ["http://localhost:4099", "http://127.0.0.1:4613", "http://[::1]:4099"] do
    test "the board's own page at #{origin} connects" do
      refute check(unquote(origin)).halted
    end
  end
end
