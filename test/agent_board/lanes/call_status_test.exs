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

  test "a call with no ticket needs attention at its deadline, not before" do
    task = %{number: 12, held: false, released_at: @at}
    deadline = DateTime.add(@at, 90)
    assert CallStatus.unanswered_at(task, 90) == deadline
    calls = %{tickets: %{}, stall_after: 90, now: deadline}
    refute CallStatus.unanswered?(task, %{calls | now: DateTime.add(deadline, -1)})
    assert CallStatus.unanswered?(task, calls)
    refute CallStatus.unanswered?(task, %{calls | tickets: %{12 => nil}})
  end

  test "a task still held has no unanswered-call deadline" do
    task = %{number: 12, held: true, released_at: @at}
    assert CallStatus.unanswered_at(task, 90) == nil

    refute CallStatus.unanswered?(task, %{
             tickets: %{},
             stall_after: 90,
             now: DateTime.add(@at, 300)
           })
  end

  test "an active ticket with no observed start or end remains pending" do
    assert CallStatus.pending_ticket?(%{})

    assert CallStatus.pending_ticket?(%{
             "stopped" => false,
             "archived" => false,
             "started_at" => nil,
             "ended_at" => nil
           })
  end

  test "stopped and archived tickets are not pending even without work timestamps" do
    for ticket <- [
          %{"stopped" => true},
          %{"archived" => true},
          %{"stopped" => true, "archived" => true}
        ] do
      refute CallStatus.pending_ticket?(ticket)
    end
  end

  test "a start or an end removes a ticket from the pending queue" do
    for ticket <- [
          %{"started_at" => @at},
          %{"ended_at" => @at},
          %{"started_at" => @at, "ended_at" => DateTime.add(@at, 60)}
        ] do
      refute CallStatus.pending_ticket?(ticket)
    end
  end

  describe "queue_stage/2" do
    @task %{number: 12, held: false, released_at: @at}
    @calls %{now: @at, tickets: %{}, stall_after: 90}

    test "waits for a ticket only for a recent call" do
      assert CallStatus.queue_stage(@task, @calls) == {:awaiting_ticket, @at}
      assert CallStatus.queue_stage(@task, %{@calls | now: DateTime.add(@at, 90)}) == nil
      assert CallStatus.queue_stage(%{@task | held: true}, @calls) == nil
    end

    test "a pending ticket uses its latest assignment time if known" do
      latest = DateTime.add(@at, 30)
      ticket = %{"assignments" => [%{"created_at" => @at}, %{"created_at" => latest}]}

      assert CallStatus.queue_stage(@task, %{@calls | tickets: %{12 => ticket}}) ==
               {:in_runner_queue, latest}

      assert CallStatus.queue_stage(@task, %{@calls | tickets: %{12 => %{}}}) ==
               {:in_runner_queue, nil}
    end

    test "started, ended, stopped and archived tickets do not display a queue stage" do
      for ticket <- [
            %{"started_at" => @at},
            %{"ended_at" => @at},
            %{"stopped" => true},
            %{"archived" => true}
          ] do
        assert CallStatus.queue_stage(@task, %{@calls | tickets: %{12 => ticket}}) == nil
      end
    end
  end

  describe "problem/2" do
    test "an incomplete claim and a completed call without a ticket report distinct problems" do
      calls = %{tickets: %{}, now: DateTime.add(@at, 120), stall_after: 90}
      held = %{held: true, number: 12, released_at: @at}
      assert CallStatus.problem(held, calls) == :failed
      assert CallStatus.problem(%{held | held: false}, calls) == :unanswered
    end

    test "a claim still in flight, a call before its deadline or a matching ticket has no problem" do
      held = %{held: true, number: 12, released_at: @at}
      released = %{held | held: false}
      calls = %{tickets: %{}, now: DateTime.add(@at, 59), stall_after: 90}
      assert CallStatus.problem(held, calls) == nil
      assert CallStatus.problem(released, calls) == nil

      assert CallStatus.problem(released, %{
               calls
               | tickets: %{12 => %{}},
                 now: DateTime.add(@at, 120)
             }) == nil
    end
  end
end
