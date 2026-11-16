defmodule AgentBoard.Lanes.Digest.VisitTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Digest.Visit
  @now ~U[2026-11-16 12:00:00Z]
  @previous ~U[2026-11-16 09:00:00Z]

  test "an explicit live visit keeps its clock and ignores an old sync timestamp" do
    assert %Visit{now: @now, last_visit: @previous, offset: 180, sync: :live} =
             Visit.from_options(
               now: @now,
               last_visit: @previous,
               tz_offset: 180,
               frozen: false,
               frozen_at: @previous
             )
  end

  test "a saved timestamp implies frozen unless overridden; missing evidence is distinct from live" do
    assert Visit.from_options(now: @now, frozen_at: @previous).sync == {:through, @previous}
    assert Visit.from_options(now: @now, frozen: true).sync == :unconfirmed
    assert %Visit{sync: :live, offset: 0, last_visit: nil} = Visit.from_options(now: @now)
  end
end
