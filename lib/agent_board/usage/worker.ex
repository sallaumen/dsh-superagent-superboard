defmodule AgentBoard.Usage.Worker do
  @moduledoc """
  The job that keeps the usage ledger current: every five minutes, in its
  own `usage` queue, it reads the files Claude Code, Codex and the DeepSeek
  Harness changed since the last run (`AgentBoard.Usage.Ledger.refresh/0`).

  The first run reads every transcript on disk, a few minutes of work; the
  next ones read only what changed. A run that outlasts the cron period is
  not doubled: the queue runs one job at a time and the next one only finds
  what is left.
  """
  use Oban.Worker, queue: :usage, max_attempts: 1, unique: [period: 240]

  alias AgentBoard.Usage.Ledger

  @impl Oban.Worker
  def perform(_job) do
    Ledger.refresh()
    :ok
  end
end
