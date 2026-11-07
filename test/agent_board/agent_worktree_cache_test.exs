defmodule AgentBoard.AgentWorktreeCacheTest do
  @moduledoc "A worktree observation is reused inside its TTL and read again after it."
  use ExUnit.Case, async: true

  alias AgentBoard.AgentWorktree.Cache

  setup do
    counter = :counters.new(1, [])

    read = fn ->
      :counters.add(counter, 1, 1)
      :counters.get(counter, 1)
    end

    %{key: {:test, make_ref()}, read: read, reads: fn -> :counters.get(counter, 1) end}
  end

  test "inside the TTL the first answer is reused", %{key: key, read: read, reads: reads} do
    assert Cache.fetch(key, 60_000, read) == 1
    assert Cache.fetch(key, 60_000, read) == 1
    assert reads.() == 1
  end

  test "an expired answer is read again", %{key: key, read: read, reads: reads} do
    assert Cache.fetch(key, 5, read) == 1
    Process.sleep(10)
    assert Cache.fetch(key, 5, read) == 2
    assert reads.() == 2
  end

  test "a TTL of zero reads every time", %{key: key, read: read, reads: reads} do
    assert Cache.fetch(key, 0, read) == 1
    assert Cache.fetch(key, 0, read) == 2
    assert reads.() == 2
  end

  test "a nil answer (no worktree) is kept like any other", %{key: key} do
    assert Cache.fetch(key, 60_000, fn -> nil end) == nil
    assert Cache.fetch(key, 60_000, fn -> flunk("read twice") end) == nil
  end
end
