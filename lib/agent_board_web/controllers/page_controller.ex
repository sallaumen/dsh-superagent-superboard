defmodule AgentBoardWeb.PageController do
  use AgentBoardWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
