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
    assert rescued.attempt == 2
    assert [%{"error" => "rescued after a board restart"}] = rescued.errors

    assert Repo.get!(Oban.Job, queued.id).state == "available"
  end
end
