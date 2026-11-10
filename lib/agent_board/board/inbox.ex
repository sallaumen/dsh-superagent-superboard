defmodule AgentBoard.Board.Inbox do
  @moduledoc "Recent agent conversations and active attention across tracked projects."
  import Ecto.Query, warn: false
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.{Board, Lanes, Repo, Workpad}
  alias AgentBoard.Board.{Comment, Task}

  @message_limit 30
  @alert_limit 30

  def snapshot do
    %{messages: messages(), alerts: alerts()}
  end

  @doc "The newest agent reply in each task, newest conversation first."
  def messages do
    latest =
      from c in Comment,
        where: c.kind == "agent",
        distinct: c.task_id,
        order_by: [asc: c.task_id, desc: c.updated_at, desc: c.id]

    Repo.all(
      from c in subquery(latest),
        join: t in Task,
        on: t.id == c.task_id,
        join: r in assoc(t, :repository),
        where: r.active == true,
        order_by: [desc: c.updated_at, desc: c.id],
        limit: @message_limit,
        select: %{
          id: c.id,
          task_id: t.id,
          number: t.number,
          title: t.title,
          repo: fragment("concat(?, '/', ?)", r.owner, r.name),
          repository: r,
          body: c.body,
          at: c.updated_at
        }
    )
    |> Enum.map(fn item ->
      item
      |> Map.put(:preview, preview(item.body))
      |> Map.put(:version, version(item.id, item.body))
    end)
  end

  @doc "Tasks that currently need the owner, separate from chat messages."
  def alerts do
    tasks =
      Repo.all(
        from t in Task,
          join: r in assoc(t, :repository),
          where:
            r.active == true and t.state in ["blocked", "question", "ready", "running"] and
              t.stopped == false and t.archived == false,
          order_by: [desc: t.state_changed_at, desc: t.id],
          limit: 100,
          preload: [repository: r]
      )

    resolved = tasks |> Enum.filter(&(&1.state == "ready")) |> Board.resolved_task_ids()
    now = DateTime.utc_now()

    tasks
    |> Enum.filter(&needs_attention?(&1, resolved, now))
    |> Enum.take(@alert_limit)
    |> Enum.map(&alert/1)
  end

  defp needs_attention?(%Task{state: "running"} = task, _resolved, now),
    do: Lanes.slow?(task, now)

  defp needs_attention?(task, resolved, _now), do: not MapSet.member?(resolved, task.id)

  # A running task is here only past the time its size allows.
  defp alert(%Task{state: "running"} = task),
    do: alert_item(task, "slow", Lanes.slow_at(task))

  defp alert(task), do: alert_item(task, task.state, task.state_changed_at || task.updated_at)

  defp alert_item(task, state, at) do
    %{
      task_id: task.id,
      number: task.number,
      title: task.title,
      repo: "#{task.repository.owner}/#{task.repository.name}",
      state: state,
      at: at
    }
  end

  defp preview(body) do
    text =
      case Workpad.parse(body) do
        nil -> body || ""
        workpad -> workpad_preview(workpad)
      end

    text
    |> String.replace(~r/<!--.*?-->/s, "")
    |> String.replace(~r/\[([^\]]+)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/[#*_`>]/, "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.join(" ")
    |> String.slice(0, 170)
    |> case do
      "" -> gettext("Message without a preview")
      compact -> compact
    end
  end

  defp workpad_preview(workpad) do
    validation = workpad.validation && workpad.validation.detail

    [workpad.question, workpad.blockage, validation, workpad.plan]
    |> Enum.find(gettext("Report updated"), &is_binary/1)
  end

  defp version(id, body) do
    :sha256
    |> :crypto.hash("#{id}:#{body}")
    |> Base.encode16(case: :lower)
  end
end
