defmodule AgentBoard.TicketOverlay do
  @moduledoc """
  How a runner ticket's state lands on the board's task row.

  Two writers share the update: the sync (every five minutes, with the GitHub
  issue in hand) and the ticket poll (every ten seconds, from the runner's
  sqlite). Each keeps its own trigger and its own guard; only the write lives
  here, so a new field or a correction lands once instead of twice.

  `:include_finished` is the sync's extra reach: it may move a task that was
  closed and whose issue was reopened. The poll only touches a task still in
  the flow (`done`/`closed` are left alone), which is why a stale ticket never
  revives finished work.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.Repo

  @doc """
  Applies one ticket state to the tasks of `repository` with `number`.

  The task's `state_changed_at` moves only when the state actually changes;
  `started_at` only moves forward (nil or older). Stopped and archived tasks
  are never touched. Returns `:ok`.
  """
  @spec apply(Repository.t(), integer(), String.t(), DateTime.t() | nil, keyword()) :: :ok
  def apply(%Repository{id: repository_id}, number, overlay, started_at, opts \\ [])
      when is_integer(number) and is_binary(overlay) do
    base =
      from t in Task,
        where:
          t.repository_id == ^repository_id and t.number == ^number and
            not t.stopped and not t.archived

    base =
      if Keyword.get(opts, :include_finished, false),
        do: base,
        else: from(t in base, where: t.state not in ["done", "closed"])

    # A confirmed GitHub reopen starts a new round of work. Apply this guard
    # in the write itself: the poller can hold a ticket read before the sync.
    at = if overlay == "done", do: opts[:ended_at], else: started_at
    base = after_reopen(base, at)

    now = DateTime.utc_now()

    Repo.update_all(from(t in base, where: t.state != ^overlay),
      set: [state: overlay, state_changed_at: now, updated_at: now]
    )

    if started_at do
      Repo.update_all(
        from(t in base, where: is_nil(t.started_at) or t.started_at < ^started_at),
        set: [started_at: started_at]
      )
    end

    :ok
  end

  defp after_reopen(base, nil), do: from(t in base, where: is_nil(t.github_reopened_at))

  defp after_reopen(base, at),
    do: from(t in base, where: is_nil(t.github_reopened_at) or t.github_reopened_at < ^at)
end
