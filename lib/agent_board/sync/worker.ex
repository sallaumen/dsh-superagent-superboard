defmodule AgentBoard.Sync.Worker do
  @moduledoc """
  The durable sync job. Oban retries it, the supervisor restarts it, and the
  dashboard shows it — no hand-rolled loop.

  Schedule it with `AgentBoard.Sync.Scheduler` (or an Oban cron plugin).
  """
  use Oban.Worker, queue: :sync, max_attempts: 3, unique: [period: 30]

  @impl Oban.Worker
  def perform(_job) do
    AgentBoard.Sync.all()
    :ok
  end
end
