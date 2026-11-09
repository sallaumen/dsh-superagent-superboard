defmodule AgentBoardWeb.DevReload do
  @moduledoc """
  The dev-only checks on every request, unless an update holds them.

  The board's service runs in dev, so these two plugs stand between a
  fast-forward and every page: see `AgentBoard.System.UpdateRun`.
  """
  use Plug.Builder

  alias AgentBoard.System.UpdateRun

  plug Phoenix.CodeReloader
  plug Phoenix.Ecto.CheckRepoStatus, otp_app: :agent_board

  def call(conn, opts) do
    if UpdateRun.reload_held?(), do: conn, else: super(conn, opts)
  end
end
