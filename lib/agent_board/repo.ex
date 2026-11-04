defmodule AgentBoard.Repo do
  use Ecto.Repo,
    otp_app: :agent_board,
    adapter: Ecto.Adapters.Postgres
end
