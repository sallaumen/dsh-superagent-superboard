defmodule AgentBoard.TicketOverlayTest do
  @moduledoc """
  The one place a ticket becomes a task state: the sync and the poll use it
  with different reach, and the guards that differ are stated here.
  """
  use AgentBoard.DataCase, async: true

  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.{Repo, TicketOverlay}
  alias AgentBoard.Runners.Execution

  @now ~U[2026-11-08 12:00:00Z]

  setup do
    repo =
      %Repository{}
      |> Repository.changeset(%{owner: "example", name: "atlas-relay"})
      |> Repo.insert!()

    %{repo: repo}
  end

  defp task!(repo, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{repository_id: repo.id, kind: "issue", number: 42, title: "Task", state: "queued"},
        attrs
      )

    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert!()
  end

  test "applies the state and records the start", %{repo: repo} do
    task = task!(repo)

    assert :ok = TicketOverlay.apply(repo, 42, "running", @now)

    task = Repo.get!(Task, task.id)
    assert task.state == "running"
    assert task.started_at == @now
    assert task.state_changed_at
  end

  test "does not move an existing start backwards", %{repo: repo} do
    earlier = DateTime.add(@now, -60, :second)
    task = task!(repo, %{started_at: @now})

    assert :ok = TicketOverlay.apply(repo, 42, "ready", earlier)

    assert Repo.get!(Task, task.id).started_at == @now
  end

  test "does not rewrite the state timestamp when the state did not change", %{repo: repo} do
    changed_at = DateTime.add(@now, -3600, :second)
    task = task!(repo, %{state: "running", state_changed_at: changed_at})

    assert :ok = TicketOverlay.apply(repo, 42, "running", @now)

    task = Repo.get!(Task, task.id)
    assert task.state == "running"
    assert task.state_changed_at == changed_at
  end

  test "never touches a stopped or archived task", %{repo: repo} do
    stopped = task!(repo, %{stopped: true})
    archived = task!(repo, %{number: 43, archived: true})

    assert :ok = TicketOverlay.apply(repo, 42, "running", @now)
    assert :ok = TicketOverlay.apply(repo, 43, "running", @now)

    assert Repo.get!(Task, stopped.id).state == "queued"
    assert Repo.get!(Task, archived.id).state == "queued"
  end

  test "a dropped Harness ticket cannot stop a local executor or overwrite its later result",
       %{repo: repo} do
    task = task!(repo, %{state: "running"})

    execution =
      %Execution{}
      |> Execution.changeset(%{
        task_id: task.id,
        repository_id: repo.id,
        executor: "codex",
        status: "running",
        run_dir: "/tmp/local-run"
      })
      |> Repo.insert!()

    assert :ok = TicketOverlay.apply(repo, 42, "stopped", nil, ended_at: @now)
    assert Repo.get!(Task, task.id).state == "running"

    execution
    |> Ecto.Changeset.change(status: "done", finished_at: ~U[2026-11-08 12:01:00.000000Z])
    |> Repo.update!()

    task |> Task.changeset(%{state: "ready"}) |> Repo.update!()
    assert :ok = TicketOverlay.apply(repo, 42, "stopped", nil, ended_at: @now)
    assert Repo.get!(Task, task.id).state == "ready"
  end

  test "only a drop after the recorded reopen ends this round of work", %{repo: repo} do
    task = task!(repo) |> Ecto.Changeset.change(github_reopened_at: @now) |> Repo.update!()
    start = DateTime.add(@now, -60)

    TicketOverlay.apply(repo, 42, "stopped", start, ended_at: @now)
    assert Repo.get!(Task, task.id).state == "queued"

    TicketOverlay.apply(repo, 42, "stopped", start, ended_at: DateTime.add(@now, 60))
    assert Repo.get!(Task, task.id).state == "stopped"
  end

  test "the poll path leaves finished work alone", %{repo: repo} do
    task = task!(repo, %{state: "done"})

    assert :ok = TicketOverlay.apply(repo, 42, "running", @now)

    assert Repo.get!(Task, task.id).state == "done"
  end

  test "the sync path may move a finished task when its issue reopened", %{repo: repo} do
    task = task!(repo, %{state: "done"})

    assert :ok = TicketOverlay.apply(repo, 42, "running", @now, include_finished: true)

    assert Repo.get!(Task, task.id).state == "running"
  end
end
