defmodule AgentBoard.Sync.WorkerTest do
  @moduledoc "The Oban job: perform/1 runs the sync and reports success."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.Sync.Worker

  test "perform/1 runs the sync and returns :ok with no repositories", _ctx do
    assert Worker.perform(%Oban.Job{args: %{}}) == :ok
  end
end
