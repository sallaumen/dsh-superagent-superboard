defmodule AgentBoard.ObanRescueTest do
  @moduledoc "A restart leaves executing rows behind; the boot sweep returns them to work."
  use AgentBoard.DataCase, async: false

  import Ecto.Query

  alias AgentBoard.{ObanRescue, Repo}

  test "executing jobs from the dead process become retryable, others stay" do
    now = DateTime.utc_now()

    orphan =
      %Oban.Job{worker: "AgentBoard.Sync.Worker", queue: "sync", args: %{}, scheduled_at: now}
      |> Repo.insert!()

    queued =
      %Oban.Job{worker: "AgentBoard.Usage.Worker", queue: "usage", args: %{}, scheduled_at: now}
      |> Repo.insert!()

    Repo.update_all(
      from(j in Oban.Job, where: j.id == ^orphan.id),
      set: [state: "executing", scheduled_at: now, attempt: 1]
    )

    assert {1, nil} = ObanRescue.rescue_orphans()

    rescued = Repo.get!(Oban.Job, orphan.id)
    assert rescued.state == "retryable"
    # The dead run already counted when it started; the next one counts itself.
    assert rescued.attempt == 1
    assert [%{"error" => "rescued after a board restart"}] = rescued.errors

    assert Repo.get!(Oban.Job, queued.id).state == "available"
  end

  test "a job out of attempts is discarded, and the others are still rescued" do
    now = DateTime.utc_now()

    usage =
      %Oban.Job{
        worker: "AgentBoard.Usage.Worker",
        queue: "usage",
        args: %{},
        scheduled_at: now,
        max_attempts: 1
      }
      |> Repo.insert!()

    sync =
      %Oban.Job{
        worker: "AgentBoard.Sync.Worker",
        queue: "sync",
        args: %{},
        scheduled_at: now,
        max_attempts: 3
      }
      |> Repo.insert!()

    Repo.update_all(
      from(j in Oban.Job, where: j.id in ^[usage.id, sync.id]),
      set: [state: "executing", attempt: 1]
    )

    assert {2, nil} = ObanRescue.rescue_orphans()

    discarded = Repo.get!(Oban.Job, usage.id)
    assert discarded.state == "discarded"
    assert discarded.attempt == 1
    assert discarded.discarded_at
    assert [%{"error" => "rescued after a board restart"}] = discarded.errors

    assert Repo.get!(Oban.Job, sync.id).state == "retryable"
  end
end
