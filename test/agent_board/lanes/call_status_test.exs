defmodule AgentBoard.Lanes.CallStatusTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.CallStatus

  @at ~U[2026-11-09 20:47:31Z]

  test "a claim is in flight until the grace period expires" do
    held = %{held: true, released_at: @at}
    refute CallStatus.failed?(held, DateTime.add(@at, 59))
    assert CallStatus.failed?(held, DateTime.add(@at, 60))
  end

  test "a completed or unclaimed release is not a failed call" do
    now = DateTime.add(@at, 120)
    refute CallStatus.failed?(%{held: false, released_at: @at}, now)
    refute CallStatus.failed?(%{held: true, released_at: nil}, now)
  end
end
