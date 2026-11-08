defmodule AgentBoard.JobRescueTest do
  @moduledoc """
  Jobs a restart leaves `executing` (docs/maintainer-contract.md, "Jobs a
  restart interrupts"). The test environment starts Oban without plugins, so
  these tests run the engine call `Oban.Lifeline` makes on the leader once a
  minute, with the board's own `rescue_after`, and then look at each worker.
  """
  use AgentBoard.DataCase, async: true

  alias AgentBoard.Repo
  alias AgentBoard.Sync.Worker, as: SyncWorker
  alias AgentBoard.Usage.Worker, as: UsageWorker

  # The longest normal run: a full read of every transcript by the usage
  # ledger, 3-4 minutes on the owner's Mac. A sync takes seconds.
  @longest_run_minutes 4

  defp config, do: Application.fetch_env!(:agent_board, Oban)

  defp rescue_after_ms do
    {Oban.Lifeline, opts} =
      config()
      |> Keyword.fetch!(:plugins)
      |> Enum.find(&match?({Oban.Lifeline, _}, &1))

    opts |> Keyword.fetch!(:rescue_after) |> Oban.Period.to_milliseconds()
  end

  defp run_lifeline,
    do: Oban.Engine.rescue_jobs(Oban.config(), Oban.Job, rescue_after: rescue_after_ms())

  # A job whose node stopped mid-run: it started `ms` ago and nothing will
  # ever acknowledge it.
  defp orphan(worker, ms) do
    at = DateTime.add(DateTime.utc_now(), -ms, :millisecond)

    %{}
    |> worker.new(
      state: "executing",
      attempt: 1,
      attempted_at: at,
      attempted_by: ["board", "a-boot-that-is-gone"],
      scheduled_at: at
    )
    |> Repo.insert!()
  end

  test "the Oban config, Lifeline's options included, is valid" do
    # The test environment drops plugins before Oban validates them, so a bad
    # option would only show when the service boots.
    assert Oban.Config.validate(config()) == :ok
  end

  test "a sync a restart left executing comes back and is cancelled as superseded" do
    job = orphan(SyncWorker, rescue_after_ms() + :timer.minutes(1))

    assert {:ok, [%{id: id, state: "available"}]} = run_lifeline()
    assert id == job.id

    rescued = Repo.reload!(job)
    assert rescued.state == "available"
    assert {:cancel, reason} = SyncWorker.perform(rescued)
    assert reason =~ "superseded"
  end

  test "a usage run a restart left executing is discarded, never run again" do
    job = orphan(UsageWorker, rescue_after_ms() + :timer.minutes(1))

    assert {:ok, [%{id: id, state: "discarded"}]} = run_lifeline()
    assert id == job.id
    assert Repo.reload!(job).state == "discarded"
  end

  test "a run longer than the longest normal one is still left executing" do
    job = orphan(UsageWorker, :timer.minutes(2 * @longest_run_minutes))

    assert {:ok, []} = run_lifeline()
    assert Repo.reload!(job).state == "executing"
  end
end
