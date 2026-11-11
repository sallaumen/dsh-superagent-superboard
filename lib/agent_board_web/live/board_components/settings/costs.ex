defmodule AgentBoardWeb.BoardComponents.Settings.Costs do
  @moduledoc """
  Settings → Costs: what the board, its agent and its voice spent, each source
  in its own currency and class (`AgentBoard.Usage.Overview`), never summed
  across currencies. A missing price is "?" or a minimum ("≥"), never zero.

  The page, the window of UTC days and the Agents filters live in the URL
  (`costs`, `days`, `source`, `project`), so a reload or a shared link reopens
  the same view. Data is read when the section opens and when the page or the
  window changes; a filter only narrows what was read; nothing polls.
  """
  use AgentBoardWeb, :live_component

  alias AgentBoard.AI
  alias AgentBoard.ElevenLabs.{Account, Usage}
  alias AgentBoard.Usage.Overview
  alias AgentBoardWeb.{BoardNavigation, FailureText, Numbers, Time}

  @pages ~w(summary agents calls)
  @days [7, 30, 90]
  @sources ~w(all dsh claude_code codex)
  @recent_calls 50
  @shown_runs 100

  @doc "The pages this section has, in order."
  def pages, do: @pages

  @doc "The windows the summary offers, in UTC days."
  def windows, do: @days

  attr :active, :boolean, default: false
  attr :repo, :map, default: nil
  attr :params, :map, default: %{}
  attr :tickets, :list, default: []
  attr :tz_offset, :integer, default: 0

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, overview: nil, executions: nil, calls: nil, loaded: nil)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    params = socket.assigns.params
    page = if params[:page] in @pages, do: params[:page], else: "summary"
    days = if params[:days] in @days, do: params[:days], else: 30
    source = if params[:source] in @sources, do: params[:source], else: "all"
    project = if is_binary(params[:project]), do: params[:project], else: "all"
    socket = assign(socket, page: page, days: days, source: source, project: project)

    # Read on opening and on a new page or window; a broadcast re-render of
    # the open section keeps what it has. The calls page has no window.
    key = if page == "calls", do: {page, nil}, else: {page, days}

    if socket.assigns.active and socket.assigns.loaded != key,
      do: {:ok, load(socket, key)},
      else: {:ok, socket}
  end

  defp load(socket, {"summary", days} = key) do
    assign(socket,
      overview: Overview.build(days, tickets: socket.assigns.tickets),
      loaded: key
    )
  end

  defp load(socket, {"agents", days} = key) do
    assign(socket,
      executions: Overview.executions(days, tickets: socket.assigns.tickets),
      loaded: key
    )
  end

  defp load(socket, {"calls", _days} = key),
    do: assign(socket, calls: AI.recent(@recent_calls), loaded: key)

  @impl true
  def handle_event("costs_view", params, socket) do
    page = if params["page"] in @pages, do: params["page"], else: socket.assigns.page

    days =
      case Integer.parse(params["days"] || "") do
        {days, ""} when days in @days -> days
        _ -> socket.assigns.days
      end

    filters = Map.take(socket.assigns, [:source, :project])
    {:noreply, push_patch(socket, to: costs_path(socket.assigns.repo, page, days, filters))}
  end

  def handle_event("costs_filter", params, socket) do
    filters = %{
      source: if(params["source"] in @sources, do: params["source"], else: "all"),
      project: if(is_binary(params["project"]), do: params["project"], else: "all")
    }

    {:noreply,
     push_patch(socket,
       to: costs_path(socket.assigns.repo, "agents", socket.assigns.days, filters)
     )}
  end

  @doc "The URL of a page, its window and, on Agents, its filters."
  def costs_path(repo, page, days, filters \\ %{}) do
    query = %{"costs" => page, "days" => days}

    query =
      if page == "agents",
        do:
          filters
          |> Enum.reject(fn {_key, value} -> value in [nil, "all"] end)
          |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
          |> Map.merge(query),
        else: query

    BoardNavigation.settings_path(repo, "costs", query)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ab-costs">
      <div class="ab-costs__bar">
        <div class="ab-segmented ab-segmented--sm" role="group" aria-label={gettext("Costs pages")}>
          <button
            :for={page <- pages()}
            id={"costs-page-" <> page}
            type="button"
            class="ab-segment"
            aria-pressed={to_string(@page == page)}
            phx-click="costs_view"
            phx-value-page={page}
            phx-target={@myself}
          >{page_label(page)}</button>
        </div>
        <div
          :if={@page != "calls"}
          class="ab-segmented ab-segmented--sm"
          role="group"
          aria-label={gettext("Window in UTC days")}
        >
          <button
            :for={days <- windows()}
            id={"costs-days-#{days}"}
            type="button"
            class="ab-segment"
            aria-pressed={to_string(@days == days)}
            phx-click="costs_view"
            phx-value-page={@page}
            phx-value-days={days}
            phx-target={@myself}
          >{gettext("%{count} days", count: days)}</button>
        </div>
      </div>

      <.summary :if={@page == "summary" and @overview} overview={@overview} tz_offset={@tz_offset} />
      <.agents
        :if={@page == "agents" and @executions}
        executions={@executions}
        source={@source}
        project={@project}
        days={@days}
        myself={@myself}
      />
      <.calls :if={@page == "calls" and @calls} calls={@calls} />
    </div>
    """
  end

  attr :overview, :map, required: true
  attr :tz_offset, :integer, default: 0

  defp summary(assigns) do
    assigns =
      assign(assigns,
        tiles: tiles(assigns.overview, DateTime.utc_now(), assigns.tz_offset),
        chart: chart(assigns.overview)
      )

    ~H"""
    <p class="ab-costs__scope">
      {gettext(
        "%{from} to %{to}, UTC days. Today is still running. Currencies are never added together.",
        from: date(@overview.since),
        to: date(@overview.today)
      )}
    </p>

    <div
      :for={
        {group, title} <- [
          money: gettext("US$ that leaves a balance"),
          plan: gettext("Plans and quotas")
        ]
      }
      class={["ab-costs__group", "is-#{group}"]}
    >
      <h4 class="ab-costs__group-title">{title}</h4>
      <ul class="ab-costs__tiles" aria-label={title}>
        <li
          :for={tile <- @tiles}
          :if={tile.group == group}
          id={"costs-" <> tile.key}
          class="ab-costs__tile"
        >
          <span class="ab-costs__tile-name">{tile.name}</span>
          <strong class="ab-costs__tile-value">{tile.value}</strong>
          <span class="ab-costs__tile-class">{tile.class}</span>
          <span
            :if={tile[:meter]}
            class="ab-costs__meter"
            role="progressbar"
            aria-label={tile.name}
            aria-valuenow={tile.meter}
            aria-valuemin="0"
            aria-valuemax="100"
          ><span style={"width: #{tile.meter}%"}></span></span>
          <span class="ab-costs__tile-fact">{tile.fact}</span>
        </li>
      </ul>
    </div>

    <section class="ab-costs__section" aria-labelledby="costs-daily-title">
      <header class="ab-costs__section-head">
        <h4 id="costs-daily-title">{gettext("US$ per UTC day")}</h4>
        <ul class="ab-costs__legend">
          <li><span class="ab-costs__swatch is-agent"></span>{gettext("Agent · DeepSeek")}</li>
          <li><span class="ab-costs__swatch is-board"></span>{gettext("Board AI")}</li>
          <li>
            <span class="ab-costs__swatch is-unknown"></span>{gettext("a price is missing: a minimum")}
          </li>
        </ul>
      </header>
      <p :if={@chart.max == 0} class="ab-meta">
        {gettext("Nothing was spent in US$ in these days.")}
      </p>
      <ol
        :if={@chart.max > 0}
        id="costs-daily"
        class={["ab-costs__chart", "is-#{@overview.days}"]}
        role="img"
        aria-label={@chart.label}
      >
        <li
          :for={bar <- @chart.bars}
          class={["ab-costs__day", bar.unknown? && "is-unknown"]}
          title={bar.title}
        >
          <span class="ab-costs__stack">
            <span class="ab-costs__seg is-board" style={"height: #{bar.board}%"}></span>
            <span class="ab-costs__seg is-agent" style={"height: #{bar.agent}%"}></span>
          </span>
          <span class="ab-costs__day-label">{bar.label}</span>
        </li>
      </ol>
      <p :if={@chart.max > 0} class="ab-costs__axis">
        {gettext("Highest day: %{amount}", amount: money(@chart.max))}
      </p>
    </section>

    <div class="ab-costs__columns">
      <section class="ab-costs__section" aria-labelledby="costs-tasks-title">
        <h4 id="costs-tasks-title">{gettext("Tasks that cost the most · DeepSeek")}</h4>
        <p :if={@overview.top_tasks == []} class="ab-meta">
          {gettext("No agent execution in these days is tied to a task.")}
        </p>
        <ol :if={@overview.top_tasks != []} id="costs-top-tasks" class="ab-costs__tasks">
          <li :for={task <- @overview.top_tasks}>
            <.link patch={task_path(task)} class="ab-costs__task">
              <span class="ab-costs__task-title">
                <span class="ab-data-sm">#{task.number}</span> {task.title}
              </span>
              <span class="ab-costs__task-repo">{task.repository}</span>
              <span class="ab-costs__task-cost">{cost_value(task.cost)}</span>
            </.link>
          </li>
        </ol>
      </section>

      <section class="ab-costs__section" aria-labelledby="costs-voice-title">
        <h4 id="costs-voice-title">{gettext("Voice · ElevenLabs")}</h4>
        <dl id="costs-voice-usage" class="ab-costs__facts">
          <div>
            <dt>{gettext("Paid characters")}</dt>
            <dd>{voice_number(@overview.voice, :tts_characters)}</dd>
          </div>
          <div>
            <dt>{gettext("Replies from the cache")}</dt>
            <dd>{voice_number(@overview.voice, :cache_hits)}</dd>
          </div>
          <div>
            <dt>{gettext("Transcribed audio")}</dt>
            <dd>{voice_minutes(@overview.voice)}</dd>
          </div>
          <div>
            <dt>{gettext("Daily cap of the board")}</dt>
            <dd>{cap_text(Usage.cap())}</dd>
          </div>
        </dl>
        <p class="ab-meta">
          {gettext("ElevenLabs sells characters, not dollars: the plan is the limit.")}
        </p>
      </section>
    </div>
    """
  end

  attr :executions, :list, required: true
  attr :source, :string, required: true
  attr :project, :string, required: true
  attr :days, :integer, required: true
  attr :myself, :any, required: true

  defp agents(assigns) do
    selected = Overview.select(assigns.executions, assigns.source, assigns.project)

    assigns =
      assign(assigns,
        selected: Enum.take(selected, @shown_runs),
        count: length(selected),
        costs: Overview.costs_by_source(selected),
        projects:
          assigns.executions
          |> Enum.map(& &1.project)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort(),
        sources: @sources
      )

    ~H"""
    <form
      id="costs-agents-filters"
      class="ab-costs__filters"
      phx-change="costs_filter"
      phx-target={@myself}
    >
      <label>
        <span>{gettext("Executor")}</span>
        <select name="source">
          <option :for={source <- @sources} value={source} selected={@source == source}>
            {source_label(source)}
          </option>
        </select>
      </label>
      <label>
        <span>{gettext("Project")}</span>
        <select name="project">
          <option value="all" selected={@project == "all"}>{gettext("All projects")}</option>
          <option :for={name <- @projects} value={name} selected={@project == name}>{name}</option>
          <option value="outside" selected={@project == "outside"}>
            {gettext("Outside the board or without a project")}
          </option>
        </select>
      </label>
    </form>

    <p id="costs-agents-total" class="ab-costs__scope">
      {agents_total(@count, @costs, @days)}
    </p>
    <p :if={@count > length(@selected)} class="ab-meta">
      {gettext("Showing the newest %{shown}.", shown: length(@selected))}
    </p>
    <p :if={@selected == []} class="ab-meta">{gettext("No execution matches these filters.")}</p>

    <ol :if={@selected != []} id="costs-runs" class="ab-costs__runs">
      <li :for={run <- @selected} id={"costs-run-#{run.source}-#{run.execution_id}"}>
        <details class="ab-costs__run">
          <summary>
            <span class="ab-costs__run-source">{source_label(run.source)}</span>
            <span class="ab-costs__run-where">{where(run)}</span>
            <span class="ab-costs__run-num is-requests">{requests_text(run.requests)}</span>
            <span class="ab-costs__run-num">{run_cost(run)}</span>
            <time
              :if={run.last_at}
              class="ab-costs__run-when"
              datetime={DateTime.to_iso8601(run.last_at)}
              title={Calendar.strftime(run.last_at, "%Y-%m-%d %H:%M UTC")}
            >{Time.ago(Time.age_seconds(run.last_at, DateTime.utc_now()))}</time>
          </summary>
          <dl class="ab-costs__facts ab-costs__run-facts">
            <div>
              <dt>{gettext("Input tokens")}</dt>
              <dd>{Numbers.grouped(run.input_tokens)}</dd>
            </div>
            <div>
              <dt>{gettext("Output tokens")}</dt>
              <dd>{Numbers.grouped(run.output_tokens)}</dd>
            </div>
            <div>
              <dt>{gettext("Cache read")}</dt>
              <dd>{Numbers.grouped(run.cache_read_tokens)}</dd>
            </div>
            <div>
              <dt>{gettext("Cache written")}</dt>
              <dd>{Numbers.grouped(run.cache_write_tokens)}</dd>
            </div>
            <div>
              <dt>{gettext("Models")}</dt>
              <dd>{Enum.join(run.models, ", ") |> blank_dash()}</dd>
            </div>
            <div>
              <dt>{gettext("Branch")}</dt>
              <dd>{blank_dash(run.git_branch)}</dd>
            </div>
            <div>
              <dt>{gettext("UTC days")}</dt>
              <dd>{run.days}</dd>
            </div>
            <div>
              <dt>{gettext("Execution")}</dt>
              <dd class="ab-costs__run-id">{run.execution_id}</dd>
            </div>
          </dl>
          <.link :if={run.task} patch={task_path(run.task)} class="ab-link">
            {gettext("Open task #%{number}", number: run.task.number)}
          </.link>
        </details>
      </li>
    </ol>
    """
  end

  attr :calls, :list, required: true

  defp calls(assigns) do
    ~H"""
    <p :if={@calls == []} class="ab-meta">{gettext("No AI calls recorded yet.")}</p>
    <p :if={@calls != []} class="ab-costs__scope">
      {ngettext(
        "The last %{count} call of the board's own AI, newest first.",
        "The last %{count} calls of the board's own AI, newest first.",
        length(@calls)
      )}
    </p>
    <div :if={@calls != []} class="ab-costs__table-wrap">
      <table id="costs-calls" class="ab-execution__ai-table">
        <caption class="ab-sr">{gettext("The board's own AI calls")}</caption>
        <thead>
          <tr>
            <th scope="col">{gettext("Function")}</th>
            <th scope="col">{gettext("Latency")}</th>
            <th scope="col">{gettext("Tokens")}</th>
            <th scope="col">{gettext("Cost")}</th>
            <th scope="col">{gettext("When")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={call <- @calls}>
            <td>
              <code title={"#{call.engine} · #{call.model}"}>{call.name || "—"}</code>
              <span :if={call.status == "error"} class="ab-execution__ai-error">
                {failure_reason(call.error)}
              </span>
            </td>
            <td class="ab-data-sm">{latency_text(call.duration_ms)}</td>
            <td class="ab-data-sm">{call_tokens(call)}</td>
            <td class="ab-data-sm">{call_cost(call)}</td>
            <td>
              <time
                datetime={DateTime.to_iso8601(call.inserted_at)}
                title={Calendar.strftime(call.inserted_at, "%Y-%m-%d %H:%M UTC")}
              >{Time.ago(Time.age_seconds(call.inserted_at, DateTime.utc_now()))}</time>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  The summary's tiles, one per source in its own currency: name, value, its
  class (measured, estimated, reference) and one fact.
  """
  @spec tiles(map(), DateTime.t(), integer()) :: [map()]
  def tiles(overview, now, offset) do
    [
      agent_tile(overview),
      board_tile(overview.board_ai),
      claude_tile(overview.agents["claude_code"]),
      codex_tile(overview.codex, offset),
      voice_tile(overview.account, now, offset)
    ]
  end

  defp agent_tile(%{agents: %{"dsh" => agent}, peak: peak}) do
    %{
      key: "agent",
      group: :money,
      name: gettext("Agent · DeepSeek"),
      value: agent_value(agent),
      class: gettext("estimated at the published price"),
      fact:
        [executions_text(agent.executions), peak_text(peak)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" · ")
    }
  end

  defp board_tile(board) do
    %{
      key: "board",
      group: :money,
      name: gettext("Board AI"),
      value: if(board.calls == 0, do: "—", else: cost_value(board.cost)),
      class: gettext("estimated at the price when it ran"),
      fact:
        if(board.calls == 0,
          do: gettext("No call in these days."),
          else:
            Enum.join(
              [
                ngettext("%{count} call", "%{count} calls", board.calls),
                ngettext("%{count} with an error", "%{count} with an error", board.errors)
              ],
              " · "
            )
        )
    }
  end

  defp claude_tile(agent) do
    %{
      key: "claude",
      group: :plan,
      name: "Claude Code",
      value: agent_value(agent),
      class: gettext("list-price reference"),
      fact: gettext("You pay the Max plan, not this; its quota is not read.")
    }
  end

  defp codex_tile(%{used_percent: percent} = quota, offset) do
    %{
      key: "codex",
      group: :plan,
      name: "Codex",
      value: "#{round(percent)}%",
      class: gettext("measured"),
      meter: min(round(percent), 100),
      fact:
        case quota.resets_at do
          %DateTime{} = at ->
            gettext("of the ChatGPT plan's week, renews %{date}", date: local_day(at, offset))

          _ ->
            gettext("of the ChatGPT plan's week")
        end
    }
  end

  defp codex_tile(nil, _offset) do
    %{
      key: "codex",
      group: :plan,
      name: "Codex",
      value: "?",
      class: gettext("unknown"),
      fact: gettext("No recent quota reading. The board does not treat it as zero.")
    }
  end

  defp voice_tile(%{subscription: %{used: used, limit: limit}} = account, now, offset)
       when limit > 0 do
    %{
      key: "voice",
      group: :plan,
      name: "ElevenLabs",
      value: "#{Numbers.grouped(used)} / #{Numbers.grouped(limit)}",
      class: gettext("measured · characters of the plan"),
      meter: min(round(used / limit * 100), 100),
      fact: account(account, now, offset)
    }
  end

  defp voice_tile(account, now, offset) do
    %{
      key: "voice",
      group: :plan,
      name: "ElevenLabs",
      value: "—",
      class: gettext("characters of the plan"),
      fact: account(account, now, offset) || gettext("The plan was not read yet.")
    }
  end

  @doc """
  The ElevenLabs plan in words, from `Account.snapshot/0`: what this period
  used and when it renews, or that the computer voice speaks because it is
  spent. Nil before the account was ever read.
  """
  @spec account(Account.t() | nil, DateTime.t(), integer()) :: String.t() | nil
  def account(%{subscription: %{} = sub} = state, now, offset) do
    cond do
      Account.plan_spent?(state, now) ->
        gettext("plan spent until %{date}: the computer voice speaks",
          date: day_or_dash(sub.resets_at, offset)
        )

      Account.refused?(state, now) ->
        refused_text(state, offset)

      sub.resets_at ->
        gettext("plan: %{used} of %{limit} characters this period, renews %{date}",
          used: Numbers.grouped(sub.used),
          limit: Numbers.grouped(sub.limit),
          date: day_or_dash(sub.resets_at, offset)
        )

      true ->
        gettext("plan: %{used} of %{limit} characters this period",
          used: Numbers.grouped(sub.used),
          limit: Numbers.grouped(sub.limit)
        )
    end
  end

  def account(state, now, offset),
    do: if(Account.refused?(state, now), do: refused_text(state, offset))

  defp refused_text(state, offset),
    do:
      gettext("a speech was refused for credits: the computer voice speaks until %{time}",
        time: Time.local_time(state.refused_until, offset)
      )

  @doc """
  The daily bars: the agent's DeepSeek and the board's calls stacked, as
  percentages of the highest day, and a label that reads the numbers aloud.
  """
  @spec chart(map()) :: %{max: non_neg_integer(), bars: [map()], label: String.t()}
  def chart(%{series: series, days: days}) do
    totals = Enum.map(series, &(micros(&1.agent) + micros(&1.board)))
    max = Enum.max(totals, fn -> 0 end)
    count = length(series)

    bars =
      series
      |> Enum.with_index()
      |> Enum.map(fn {day, index} ->
        %{
          agent: percent_of(micros(day.agent), max),
          board: percent_of(micros(day.board), max),
          unknown?: is_nil(day.agent) or not day.agent.complete? or not day.board.complete?,
          label: day_label(day.day, index, count, days),
          title: day_title(day)
        }
      end)

    agent = Overview.total(Enum.map(series, & &1.agent))
    board = Overview.total(Enum.map(series, & &1.board))

    %{
      max: max,
      bars: bars,
      label:
        gettext("US$ per UTC day in %{count} days: agent %{agent}, board AI %{board}",
          count: days,
          agent: cost_value(agent),
          board: cost_value(board)
        )
    }
  end

  defp micros(%{micros: micros}), do: micros
  defp micros(nil), do: 0

  defp percent_of(_value, 0), do: 0
  defp percent_of(value, max), do: Float.round(value / max * 100, 1)

  defp day_label(day, index, count, days) do
    step = if days == 7, do: 1, else: div(days, 6)

    cond do
      index == count - 1 -> Calendar.strftime(day, "%d/%m")
      rem(count - 1 - index, step) == 0 -> Calendar.strftime(day, "%d")
      true -> ""
    end
  end

  defp day_title(%{day: day, agent: agent, board: board}) do
    gettext("%{date} UTC · agent %{agent} · board AI %{board}",
      date: Date.to_iso8601(day),
      agent: cost_value(agent),
      board: cost_value(board)
    )
  end

  defp agent_value(%{ran?: false}), do: "—"
  defp agent_value(%{cost: nil}), do: "?"
  defp agent_value(%{cost: cost}), do: cost_value(cost)

  @doc "A cost as the board writes it: ≈ when complete, ≥ when a minimum, ? when unknown."
  @spec cost_value(map() | nil) :: String.t()
  def cost_value(nil), do: "?"
  def cost_value(%{micros: micros, complete?: true}), do: "≈ " <> money(micros)
  def cost_value(%{micros: micros}), do: "≥ " <> money(micros)

  defp money(0), do: Numbers.usd(0)
  defp money(micros) when micros < 5_000, do: "< " <> Numbers.usd(10_000)
  # From a thousand dollars up the cents are noise.
  defp money(micros), do: Numbers.usd(micros, cents: micros < 1_000_000_000)

  defp executions_text(0), do: gettext("did not run in these days")

  defp executions_text(count),
    do: ngettext("%{count} execution", "%{count} executions", count)

  defp peak_text(%{share: share}),
    do: gettext("%{percent}% of it at the peak rate", percent: round(share * 100))

  defp peak_text(nil), do: nil

  defp page_label("summary"), do: gettext("Summary")
  defp page_label("agents"), do: gettext("Agents")
  defp page_label("calls"), do: gettext("Board AI calls")

  defp source_label("all"), do: gettext("All executors")
  defp source_label("dsh"), do: "DeepSeek"
  defp source_label("claude_code"), do: "Claude Code"
  defp source_label("codex"), do: "Codex"
  defp source_label(source), do: source

  defp where(%{task: %{number: number, title: title}}), do: "##{number} #{title}"
  defp where(%{project: project}) when is_binary(project), do: project

  defp where(%{outside: outside}) when is_binary(outside),
    do: gettext("outside the board · %{name}", name: outside)

  defp where(_run), do: gettext("without a project")

  defp requests_text(count),
    do: ngettext("%{n} request", "%{n} requests", count, n: Numbers.grouped(count))

  # Codex has no US$: its currency is the weekly quota (see the summary).
  defp run_cost(%{source: "codex"}), do: gettext("quota")

  defp run_cost(%{source: "claude_code", cost: cost}),
    do: cost_value(cost) <> " " <> gettext("list")

  defp run_cost(%{cost: cost}), do: cost_value(cost)

  defp agents_total(count, costs, days) do
    parts =
      [
        ngettext(
          "%{count} execution in %{days} days",
          "%{count} executions in %{days} days",
          count,
          days: days
        )
      ] ++
        for {source, cost} <- Enum.sort(costs) do
          label = source_label(source)

          if source == "claude_code",
            do: "#{label} #{cost_value(cost)} " <> gettext("list"),
            else: "#{label} #{cost_value(cost)}"
        end

    Enum.join(parts, " · ")
  end

  defp blank_dash(value) when value in [nil, ""], do: "—"
  defp blank_dash(value), do: value

  defp task_path(task) do
    "/?" <>
      URI.encode_query(%{
        "repo" => "#{task.owner}/#{task.repository}",
        "panel" => "conversation",
        "task" => task.task_id
      })
  end

  defp voice_number(nil, _key), do: "?"
  defp voice_number(voice, key), do: Numbers.grouped(Map.fetch!(voice, key))

  defp voice_minutes(nil), do: "?"

  defp voice_minutes(%{stt_seconds: seconds}),
    do: gettext("%{minutes} min", minutes: Numbers.decimal(seconds / 60, 1))

  defp cap_text(0), do: gettext("none")

  defp cap_text(cap),
    do: gettext("%{count} characters", count: Numbers.grouped(cap))

  defp date(day), do: "#{day.day} #{Time.month(day)}"

  defp local_day(at, offset), do: date(Time.local_date(at, offset))

  defp day_or_dash(nil, _offset), do: "—"
  defp day_or_dash(at, offset), do: local_day(at, offset)

  defp call_tokens(call) do
    if is_integer(call.input_tokens) and is_integer(call.output_tokens),
      do: Numbers.grouped(call.input_tokens + call.output_tokens),
      else: "—"
  end

  # A call with tokens and no price: the model is missing from the table.
  defp call_cost(%{cost_micros: micros}) when is_integer(micros) and micros > 0,
    do: Numbers.usd_exact(micros)

  defp call_cost(%{status: "ok", input_tokens: input, output_tokens: output})
       when is_integer(input) and is_integer(output) and input + output > 0,
       do: "?"

  defp call_cost(_call), do: "—"

  defp latency_text(nil), do: "—"
  defp latency_text(ms) when is_integer(ms), do: Numbers.grouped(ms) <> " ms"

  defp failure_reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> gettext("Reason not recorded")
      word -> FailureText.text(stored_reason(word))
    end
  end

  defp failure_reason(_reason), do: gettext("Reason not recorded")

  # `AgentBoard.AI` stores a failure as a word; this is the word back as the
  # reason `FailureText` has a sentence for. An unknown word is shown as is.
  @reason_words %{
    "not_configured" => :not_configured,
    "auth_expired" => :auth_expired,
    "usage_limit" => :usage_limit,
    "timeout" => :timeout,
    "unreachable" => :unreachable
  }

  defp stored_reason("http " <> status), do: {:http, String.to_integer(status)}
  defp stored_reason(word), do: Map.get(@reason_words, word, word)
end
