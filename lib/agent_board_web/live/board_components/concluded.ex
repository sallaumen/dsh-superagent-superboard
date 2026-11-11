defmodule AgentBoardWeb.BoardComponents.Concluded do
  @moduledoc """
  History: the tasks that ended, in the order they ended, and the way back
  into each one. The merged pull requests are the panel's other list.
  """
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.StatusMark, only: [status_mark: 1]

  alias AgentBoard.Time
  alias AgentBoard.Usage.TaskCosts
  alias AgentBoardWeb.BoardComponents.Inspector

  attr :list, :string, required: true
  attr :query, :string, required: true
  attr :ended, :map, required: true
  attr :offset, :integer, required: true
  slot :inner_block, required: true

  def history(assigns) do
    now = DateTime.utc_now()

    assigns =
      assigns
      |> assign(:today, Time.local_date(now, assigns.offset))
      |> assign(:days, days(assigns.ended.items, assigns.offset))
      # in memory, recomputed by the usage worker: no ledger read per render
      |> assign(:costs, TaskCosts.for_tasks(Enum.map(assigns.ended.items, & &1.id)))
      |> assign(:costs_at, TaskCosts.computed_at())

    ~H"""
    <div id="history" class="ab-history">
      <div class="ab-history__bar">
        <div class="ab-segmented ab-segmented--sm" role="group" aria-label={gettext("What to list")}>
          <button
            :for={{id, label} <- [{"tasks", gettext("Ended tasks")}, {"prs", gettext("Merged PRs")}]}
            type="button"
            class={["ab-segment", @list == id && "is-selected"]}
            aria-pressed={to_string(@list == id)}
            phx-click="show_panel"
            phx-value-panel="history"
            phx-value-list={id}
          >{label}</button>
        </div>

        <form
          :if={@list == "tasks"}
          id="history-search"
          class="ab-history__search"
          phx-change="history_search"
          phx-submit="history_search"
        >
          <input
            type="search"
            name="q"
            value={@query}
            phx-debounce="300"
            autocomplete="off"
            aria-label={gettext("Search ended tasks by number or title")}
            placeholder={gettext("Number or title")}
          />
        </form>
      </div>

      <div class="ab-history__prs" hidden={@list != "prs"}>
        {render_slot(@inner_block)}
      </div>

      <div
        :if={@list == "tasks"}
        id="ended-list"
        class="ab-ended"
        role="region"
        tabindex="0"
        aria-label={gettext("Ended tasks, newest first")}
        phx-viewport-bottom={if @ended.has_more, do: "load_more_ended"}
      >
        <section :for={{date, items} <- @days} class="ab-ended__day">
          <h3>{if date, do: Time.day_label(date, @today), else: gettext("No date recorded")}</h3>
          <button
            :for={item <- items}
            type="button"
            id={"ended-#{item.id}"}
            class="ab-ended__row"
            phx-click="open"
            phx-value-id={item.id}
          >
            <.status_mark kind={kind(item.outcome)} word={word(item.outcome)} />
            <span class="ab-ended__title">
              <span class="ab-need__id">#{item.number}</span> {item.title}
            </span>
            <span
              class="ab-ended__cost ab-data-sm"
              title={cost_title(@costs_at, @offset)}
            >
              {cost_text(Map.get(@costs, item.id))}
            </span>
            <span class="ab-ended__pr ab-data-sm">
              {if item.pull, do: "PR ##{item.pull.number}", else: "—"}
            </span>
            <span class="ab-ended__at ab-data-sm">
              {if item.ended_at, do: Time.local_time(item.ended_at, @offset), else: "—"}
            </span>
          </button>
        </section>

        <p :if={@ended.items == [] and @query == ""} class="ab-ended__note">
          {gettext("No task has ended here yet.")}
        </p>
        <p :if={@ended.items == [] and @query != ""} class="ab-ended__note">
          {gettext("No ended task matches \"%{query}\". Try its number or a word of the title.",
            query: @query
          )}
        </p>
        <p :if={@ended.items != [] and @ended.has_more} class="ab-ended__note">
          {gettext("Scroll for older tasks")}
        </p>
        <p :if={@ended.items != [] and not @ended.has_more} class="ab-ended__note">
          {ngettext(
            "%{count} task · end of the record",
            "%{count} tasks · end of the record",
            length(@ended.items)
          )}
        </p>
      </div>
    </div>
    """
  end

  # Consecutive rows of one local day share a heading; the page is already
  # newest first, so the order of the groups is the order of the rows.
  defp days(items, offset) do
    items
    |> Enum.chunk_by(&(&1.ended_at && Time.local_date(&1.ended_at, offset)))
    |> Enum.map(fn [first | _] = chunk ->
      {first.ended_at && Time.local_date(first.ended_at, offset), chunk}
    end)
  end

  defp kind(:merged), do: :done
  defp kind(:stopped), do: :blocked
  defp kind(_closed_or_archived), do: :queue

  defp word(:merged), do: pgettext("task status", "Merged")
  defp word(:closed), do: gettext("Closed, no merged PR")
  defp word(:stopped), do: pgettext("ended task", "Stopped")
  defp word(:archived), do: pgettext("ended task", "Archived")

  # What the task's executors cost, each in its own unit and never summed
  # across them (`TaskCosts`). No entry is "—": nothing attributed in the
  # window, or not computed yet; it is never a zero.
  def cost_text(nil), do: "—"

  def cost_text(entries) do
    case Enum.filter(entries, & &1.cost) do
      [] ->
        gettext("cost unknown")

      priced ->
        Enum.map_join(priced, " · ", fn entry ->
          "#{Inspector.executor_label(entry.source)} #{Inspector.execution_cost(entry)}"
        end)
    end
  end

  defp cost_title(nil, _offset),
    do:
      gettext(
        "The executor cost is computed every five minutes; not yet since the board started."
      )

  defp cost_title(at, offset),
    do:
      gettext(
        "What the executor spent on this task in the last 90 days, from the usage ledger, at %{time}. Each executor in its own unit; the board's own calls are in the task.",
        time: Time.local_time(at, offset)
      )
end
