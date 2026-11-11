defmodule AgentBoard.Board.Inbox do
  @moduledoc "Recent agent conversations and active attention across tracked projects."
  import Ecto.Query, warn: false
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.AI.{Budget, Call, Providers}
  alias AgentBoard.{Board, Lanes, Repo, Workpad}
  alias AgentBoard.Board.{Comment, Task}
  alias AgentBoard.ElevenLabs.Account

  @message_limit 30
  @alert_limit 30

  def snapshot do
    %{messages: messages(), alerts: alerts(), providers: providers()}
  end

  @doc """
  The providers that cannot serve right now, for the Attention bell: the
  ElevenLabs plan spent (the computer voice speaks), the board's daily AI
  budget spent, and a provider whose newest board call in the last day was
  refused for its limit or balance. Each item opens the settings section
  that explains it. Derived on each read; nothing is stored.
  """
  @spec providers(DateTime.t()) :: [map()]
  def providers(now \\ DateTime.utc_now()) do
    [eleven_labs(now), ai_budget() | ai_refusals(now)] |> Enum.reject(&is_nil/1)
  end

  defp eleven_labs(now) do
    if Account.spent?(now) do
      %{
        key: "elevenlabs",
        title: gettext("ElevenLabs credits spent"),
        detail: gettext("The computer voice speaks instead."),
        section: "costs"
      }
    end
  end

  defp ai_budget do
    if Budget.check(:fast) == {:error, :budget_exhausted} do
      %{
        key: "ai-budget",
        title: gettext("The board's AI budget for today is spent"),
        detail: gettext("Its own calls wait for 00:00 UTC."),
        section: "execution"
      }
    end
  end

  defp ai_refusals(now) do
    since = DateTime.add(now, -86_400, :second)

    Repo.all(
      from c in Call,
        where: c.inserted_at >= ^since,
        distinct: c.engine,
        order_by: [asc: c.engine, desc: c.inserted_at, desc: c.id],
        select: %{engine: c.engine, status: c.status, error: c.error}
    )
    |> Enum.filter(&(&1.status == "error" and &1.error == ":usage_limit"))
    |> Enum.map(fn %{engine: engine} ->
      %{
        key: "ai-#{engine}",
        title: gettext("%{provider} refused the board's calls", provider: provider_label(engine)),
        detail:
          gettext("Its limit or balance ran out; the board tries the next provider with a key."),
        section: "execution"
      }
    end)
  end

  defp provider_label(engine) do
    Enum.find_value(Providers.all(), engine, fn {id, %{label: label}} ->
      if Atom.to_string(id) == engine, do: label
    end)
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
