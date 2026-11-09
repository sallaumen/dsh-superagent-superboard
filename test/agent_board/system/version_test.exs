defmodule AgentBoard.System.VersionTest do
  @moduledoc "Served, available and the state between them."
  use ExUnit.Case, async: false

  alias AgentBoard.System.Version

  test "served is cached and non-empty" do
    first = Version.served()
    assert is_binary(first)
    assert Version.served() == first
  end

  test "status carries the served sha and a state" do
    status = Version.status()
    assert is_binary(status.served)
    assert is_boolean(status.dirty)
    assert is_list(status.commits)
    assert status.state in [:up_to_date, :behind, :restart, :ahead, :unknown]
  end

  test "the checkout can be current while this VM still serves an older sha" do
    assert Version.state("abc1234", "abc1234", 0) == :up_to_date
    assert Version.state("abc1234", "def5678", 0) == :restart
    assert Version.state("abc1234", "def5678", 2) == :behind
    assert Version.state("abc1234", "def5678", nil) == :unknown
  end

  test "without a fetch, available is nil and the state is unknown" do
    :persistent_term.erase(:agent_board_available)
    assert Version.available() == nil
    assert Version.status().state == :unknown
  end
end
