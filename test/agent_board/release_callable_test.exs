defmodule AgentBoard.ReleaseCallableTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.Task
  alias AgentBoard.Release

  @called ~U[2026-11-09 20:47:31Z]

  test "a held task is callable without a previous call" do
    assert Release.callable?(%Task{held: true, state: "queued"}) == true
  end

  test "a previously called task is callable again while queued" do
    assert Release.callable?(%Task{held: false, state: "queued", released_at: @called}) == true

    assert Release.callable?(%Task{
             held: false,
             state: "queued",
             executor: "dsh",
             inserted_at: @called
           }) == true
  end

  test "a previously called task is not callable once running" do
    assert Release.callable?(%Task{held: false, state: "running", released_at: @called}) == false
  end

  test "an unheld queued task that was never called is not callable" do
    task = %Task{held: false, state: "queued", executor: "codex", inserted_at: @called}
    assert Release.callable?(task) == false
  end
end
