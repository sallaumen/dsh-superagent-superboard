defmodule AgentBoardWeb.BoardComponents.Settings.Execution do
  @moduledoc """
  Settings → Execution: the global pause, the three executors in their own
  currency, their limits and the board's own AI calls.

  The report is read when the section opens and when the window changes; the
  controls are a draft of the board settings. Saving writes one
  `change_setting` action per key, the same registry the voice and the API
  use. Executors are never summed.
  """
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoard.{Actions, Runners}
  alias AgentBoard.Usage.Report
  alias AgentBoardWeb.{FailureText, Time}

  @days [7, 30]
  @draft_keys ~w(monthly_usd task_usd timeout_minutes reserve_percent claude_model codex_model)
  @sources ["claude_code", "codex", "dsh"]

  attr :active, :boolean, default: false
  attr :dispatch_paused, :boolean, default: false
  attr :tickets, :list, default: []
  attr :ai_calls, :list, default: []
  attr :ai_status, :any, default: :unknown
  attr :parent, :any, default: nil
  attr :tz_offset, :integer, default: 0

  # The settings menu is on every page, so this mounts on every load: the
  # snapshot (which prices the month) is read when the section opens.
  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       days: 7,
       days_list: @days,
       sources: @sources,
       snapshot: nil,
       saved: %{},
       draft: %{},
       dirty: [],
       report: nil,
       error: nil,
       saved_notice: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    was_active = socket.assigns[:active] == true
    socket = assign(socket, assigns)

    if socket.assigns.active and not was_active do
      snapshot = Runners.snapshot()
      saved = saved_values(snapshot)
      draft = if socket.assigns.dirty == [], do: saved, else: socket.assigns.draft

      {:ok,
       socket
       |> assign(snapshot: snapshot, saved: saved, draft: draft, error: nil, saved_notice: false)
       |> assign_dirty()
       |> load_report()}
    else
      {:ok, socket}
    end
  end

  defp load_report(socket) do
    since = Report.since(socket.assigns.days)

    assign(socket,
      report: %{
        executors: Report.executors(since, tickets: socket.assigns.tickets),
        daily: Report.daily(since)
      }
    )
  end

  @impl true
  def handle_event("days", %{"days" => days}, socket) do
    days = if days in ["7", "30"], do: String.to_integer(days), else: socket.assigns.days

    {:noreply, socket |> assign(days: days) |> load_report()}
  end

  def handle_event("change", params, socket) do
    draft = Map.merge(socket.assigns.draft, Map.take(params, @draft_keys))

    {:noreply,
     socket
     |> assign(draft: draft, error: nil, saved_notice: false)
     |> assign_dirty()}
  end

  def handle_event("discard", _params, socket) do
    {:noreply,
     socket
     |> assign(draft: socket.assigns.saved, dirty: [], error: nil, saved_notice: false)}
  end

  def handle_event("save", params, socket) do
    draft = Map.merge(socket.assigns.draft, Map.take(params, @draft_keys))

    case validate(draft) do
      {:ok, values} ->
        Enum.each(Map.to_list(values), fn {key, value} ->
          :ok = Actions.run(:change_setting, %{setting: key, value: value}, Actions.owner(:ui))
        end)

        snapshot = Runners.snapshot()
        saved = saved_values(snapshot)

        {:noreply,
         assign(socket,
           snapshot: snapshot,
           saved: saved,
           draft: saved,
           dirty: [],
           error: nil,
           saved_notice: true
         )}

      {:error, message} ->
        {:noreply, assign(socket, draft: draft, error: message, saved_notice: false)}
    end
  end

  defp assign_dirty(socket) do
    dirty =
      @draft_keys
      |> Enum.filter(&(Map.get(socket.assigns.draft, &1) != Map.get(socket.assigns.saved, &1)))

    assign(socket, :dirty, dirty)
  end

  defp validate(draft) do
    with {:ok, monthly} <- float(draft["monthly_usd"], gettext("monthly cap"), empty: :zero),
         {:ok, task} <- float(draft["task_usd"], gettext("task cap")),
         {:ok, timeout} <- integer(draft["timeout_minutes"], gettext("time per task"), 1),
         {:ok, reserve} <- integer(draft["reserve_percent"], gettext("quota reserve"), 0),
         true <- reserve <= 100 || {:error, gettext("Quota reserve must be between 0 and 100%.")},
         claude = String.trim(draft["claude_model"] || ""),
         codex = String.trim(draft["codex_model"] || ""),
         true <- claude != "" || {:error, gettext("Choose a Claude Code model.")},
         true <- codex != "" || {:error, gettext("Choose a Codex model.")} do
      {:ok,
       %{
         "dispatch_monthly_usd" => if(monthly == 0.0, do: "0", else: number(monthly)),
         "dispatch_task_usd" => number(task),
         "dispatch_codex_timeout_minutes" => Integer.to_string(timeout),
         "dispatch_reserve_percent" => Integer.to_string(reserve),
         "dispatch_claude_model" => claude,
         "dispatch_codex_model" => codex
       }}
    else
      {:error, message} -> {:error, message}
      false -> {:error, gettext("Check the dispatch numbers.")}
    end
  end

  defp float(value, label, opts \\ []) do
    # The board shows money with a decimal comma, and so does a pt-BR keypad.
    value = value |> to_string() |> String.trim() |> String.replace(",", ".")

    if value == "" and Keyword.get(opts, :empty) == :zero do
      {:ok, 0.0}
    else
      case Float.parse(value) do
        {number, ""} when number >= 0 ->
          {:ok, number}

        _ ->
          {:error,
           gettext("%{label} must be a number greater than or equal to zero.", label: label)}
      end
    end
  end

  defp integer(value, label, min) do
    case Integer.parse(String.trim(to_string(value || ""))) do
      {number, ""} when number >= min ->
        {:ok, number}

      _ ->
        {:error,
         gettext("%{label} must be an integer greater than or equal to %{min}.",
           label: label,
           min: min
         )}
    end
  end

  defp saved_values(snapshot) do
    %{
      "monthly_usd" => if(snapshot.monthly_usd > 0, do: number(snapshot.monthly_usd), else: ""),
      "task_usd" => number(snapshot.task_usd),
      "timeout_minutes" => to_string(snapshot.codex_timeout_minutes),
      "reserve_percent" => to_string(snapshot.reserve_percent),
      "claude_model" => Runners.claude_model(),
      "codex_model" => Runners.codex_model()
    }
  end

  defp number(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp number(value), do: to_string(value)

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:dirty_count, length(assigns.dirty))
      |> assign(:dirty_labels, Enum.map_join(assigns.dirty, ", ", &label/1))

    ~H"""
    <div id={@id} class="ab-execution">
      <div class="ab-execution__pause">
        <div>
          <strong>{gettext("Pause new dispatches")}</strong>
          <p>
            {if @dispatch_paused,
              do: gettext("Paused. Nothing new starts and running work finishes."),
              else: gettext("Off. When you turn it on, nothing new starts and running work finishes.")}
          </p>
        </div>
        <button
          id="toggle-dispatch"
          type="button"
          class="settings-pause__switch"
          role="switch"
          aria-label={gettext("Pause new dispatches")}
          aria-checked={to_string(@dispatch_paused)}
          phx-click="toggle_dispatch"
        ><span aria-hidden="true"></span></button>
      </div>

      <div class="ab-execution__heading">
        <h4>{gettext("Executors")}</h4>
        <div
          class="ab-segmented ab-segmented--sm ab-execution__range"
          role="group"
          aria-label={gettext("Executor window")}
        >
          <button
            :for={days <- @days_list}
            type="button"
            class="ab-segment"
            aria-pressed={to_string(@days == days)}
            phx-click="days"
            phx-value-days={days}
            phx-target={@myself}
          >{gettext("%{count} days", count: days)}</button>
        </div>
      </div>

      <p :if={is_nil(@report)} class="ab-meta" role="status">
        {gettext("Reading the usage ledger…")}
      </p>

      <form
        id="execution-settings-form"
        phx-change="change"
        phx-submit="save"
        phx-target={@myself}
        phx-auto-recover="ignore"
        class="ab-execution__form"
      >
        <div :if={@report} class="ab-execution__executors">
          <article :for={source <- @sources} id={"executor-" <> source} class="ab-executor">
            <.executor_block
              source={source}
              executor={executor(@report, source)}
              draft={@draft}
              snapshot={@snapshot}
              days={@days}
              daily={@report.daily}
              parent={@parent}
            />
          </article>
        </div>

        <section class="ab-execution__ai" aria-labelledby="execution-ai-title">
          <header class="ab-execution__ai-head">
            <div>
              <h4 id="execution-ai-title">{gettext("The board's own AI calls")}</h4>
              <p class="ab-meta">
                {ai_line(AgentBoard.AI.answering())}
              </p>
            </div>
            <span class={["ab-execution__ai-state", ai_tone(@ai_status)]}>
              <.glyph kind={:stale} />{ai_label(@ai_status)}
            </span>
          </header>

          <p :if={@ai_calls == []} class="ab-meta">{gettext("No AI calls recorded yet.")}</p>
          <p :if={@ai_calls != []} class="ab-meta">
            {ngettext(
              "Last %{count} call on the board.",
              "Last %{count} calls on the board.",
              length(@ai_calls)
            )}
          </p>

          <table :if={@ai_calls != []} class="ab-execution__ai-table">
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
              <tr :for={call <- @ai_calls}>
                <td>
                  <code title={"#{call.engine} · #{call.model}"}>{call.name || "—"}</code>
                  <span :if={call.status == "error"} class="ab-execution__ai-error">
                    {failure_reason(call.error)}
                  </span>
                </td>
                <td class="ab-data-sm">{latency_text(call.duration_ms)}</td>
                <td class="ab-data-sm">{ai_tokens(call)}</td>
                <td class="ab-data-sm">{ai_cost(call.cost_micros)}</td>
                <td>
                  <time
                    datetime={DateTime.to_iso8601(call.inserted_at)}
                    title={
                      Calendar.strftime(
                        call.inserted_at,
                        "%Y-%m-%d %H:%M UTC"
                      )
                    }
                  >{ago(call.inserted_at)}</time>
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <div class="ab-execution__savebar">
          <p class={["ab-execution__dirty", @error && "is-error"]} role="status">
            {if @error,
              do: @error,
              else: dirty_text(@dirty_count, @dirty_labels)}
          </p>
          <div class="ab-execution__save-actions">
            <button
              type="button"
              class="ab-btn"
              phx-click="discard"
              phx-target={@myself}
              disabled={@dirty_count == 0}
            >{gettext("Discard")}</button>
            <button
              type="submit"
              class="ab-btn ab-btn--primary"
              disabled={@dirty_count == 0}
              phx-disable-with={gettext("Saving…")}
            >{gettext("Save limits")}</button>
          </div>
        </div>
        <p :if={@saved_notice} class="settings-saved" role="status">{gettext("Limits saved.")}</p>
      </form>
    </div>
    """
  end

  attr :source, :string, required: true
  attr :executor, :map, default: nil
  attr :draft, :map, required: true
  attr :snapshot, :map, required: true
  attr :days, :integer, required: true
  attr :daily, :list, required: true
  attr :parent, :any, default: nil

  defp executor_block(assigns) do
    ~H"""
    <header class="ab-executor__head">
      <h5>{label_for(@source)}</h5>
      <span class={["ab-tag", source_tag(@source, @executor)]}>{source_tag_text(@source, @executor)}</span>
    </header>

    <div class="ab-executor__body">
      <div class="ab-executor__usage">
        <p class="ab-executor__value">{value(@source, @executor)}</p>
        <p class="ab-executor__subtitle">{subtitle(@source, @days)}</p>

        <div
          :if={@source != "codex" and not is_nil(@executor)}
          class="ab-executor__bars"
          role="img"
          aria-label={gettext("Usage per UTC day for %{name}", name: label_for(@source))}
        >
          <span
            :for={{day, row, index} <- bars(@daily, @source, @days)}
            class={["ab-executor__bar", bar_state(row, @source)]}
            style={"--bar-height: #{bar_height(row, @source, @daily)}%"}
            title={day_title(day, row, @source)}
          >
            <span class="ab-executor__bar-fill"></span>
            <span class="ab-executor__bar-label">{bar_label(day, index, @days)}</span>
          </span>
        </div>

        <div
          :if={@source == "codex" and not is_nil(@executor) and not is_nil(@executor.quota)}
          class="ab-executor__quota"
          role="progressbar"
          aria-valuenow={quota_percent(@executor)}
          aria-valuemin="0"
          aria-valuemax="100"
          aria-label={gettext("Codex weekly quota used")}
        >
          <span style={"width: #{quota_percent(@executor)}%"}></span>
        </div>

        <p :if={@executor} class="ab-executor__facts">{facts(@source, @executor)}</p>

        <p :if={not is_nil(@executor) and @source == "codex"} class="ab-executor__quota-note">
          {quota_note(@executor)}
        </p>
      </div>

      <div class="ab-executor__controls">
        <%= if @source == "dsh" do %>
          <div class="ab-executor__limits-card">
            <p class="ab-meta">
              {gettext(
                "The DeepSeek limits live in each project: how many agents and who may call them."
              )}
            </p>
            <button
              type="button"
              class="ab-btn ab-btn--sm"
              phx-click="select_section"
              phx-value-section="projects"
              phx-target={@parent}
            >{gettext("Open Projects")}</button>
          </div>
        <% end %>

        <%= if @source == "claude_code" do %>
          <label>
            <span>{gettext("Monthly cap · US$")}</span>
            <input
              name="monthly_usd"
              value={@draft["monthly_usd"]}
              placeholder={gettext("no cap")}
              inputmode="decimal"
            />
          </label>
          <label>
            <span>{gettext("Task cap · US$")}</span>
            <input name="task_usd" value={@draft["task_usd"]} inputmode="decimal" />
          </label>
          <label>
            <span>{gettext("Model")}</span>
            <input name="claude_model" value={@draft["claude_model"]} />
          </label>
          <p
            :if={@snapshot.monthly_usd == 0 and match?({:ok, _}, @snapshot.spent)}
            class="ab-executor__warning"
          >
            {gettext(
              "No monthly cap: this month already adds up to %{amount} at list price. The caps use the same account.",
              amount: money(elem(@snapshot.spent, 1))
            )}
          </p>
          <p :if={@snapshot.spent == {:error, :budget_unknown}} class="ab-executor__warning">
            {sentence(
              gettext("This month's spend has a model without a price; the ceiling cannot be checked")
            )}
          </p>
        <% end %>

        <%= if @source == "codex" do %>
          <label>
            <span>{gettext("Quota reserve · %")}</span>
            <input name="reserve_percent" value={@draft["reserve_percent"]} inputmode="numeric" />
          </label>
          <label>
            <span>{gettext("Time per task · min")}</span>
            <input name="timeout_minutes" value={@draft["timeout_minutes"]} inputmode="numeric" />
          </label>
          <label>
            <span>{gettext("Model")}</span>
            <input name="codex_model" value={@draft["codex_model"]} />
          </label>
        <% end %>
      </div>
    </div>
    """
  end

  defp executor(report, source), do: Enum.find(report.executors, &(&1.source == source))

  defp label_for("claude_code"), do: "Claude Code"
  defp label_for("codex"), do: "Codex"
  defp label_for("dsh"), do: "DeepSeek"
  defp label_for(source), do: source

  defp source_tag(_source, nil), do: "ab-tag--stale"
  defp source_tag("codex", executor) when not is_nil(executor), do: "ab-tag--agent"
  defp source_tag(_source, _executor), do: "ab-tag--you"

  defp source_tag_text("codex", _executor), do: gettext("measured")
  defp source_tag_text("dsh", _executor), do: gettext("estimated, minimum")
  defp source_tag_text(_source, _executor), do: gettext("estimated")

  defp value("codex", %{quota: %{used_percent: percent}}) when is_number(percent),
    do: "#{percent(percent)}%"

  defp value("codex", _executor), do: "—"
  defp value("dsh", %{cost: %{micros: micros}}), do: "≥ " <> money_micros(micros)
  defp value(_source, nil), do: "—"
  defp value(_source, %{cost: nil}), do: "—"

  defp value(_source, %{cost: %{micros: micros, complete?: true, unknown: 0}}),
    do: "≈ " <> money_micros(micros)

  defp value(_source, %{cost: %{micros: micros}}), do: "≥ " <> money_micros(micros)

  defp subtitle("claude_code", days) do
    gettext(
      "in %{count} days, at list price. It is a reference: you pay the Max plan, not this.",
      count: days
    )
  end

  defp subtitle("codex", _days),
    do: gettext("of the weekly quota of the ChatGPT plan")

  defp subtitle("dsh", days) do
    gettext(
      "in %{count} days, at the board price. Cache reads without a price make this a floor.",
      count: days
    )
  end

  defp facts("codex", executor) do
    Enum.join(
      [
        sessions_text(executor.executions),
        requests_text(executor.requests),
        gettext("%{input} in / %{output} out",
          input: tokens(executor.input_tokens),
          output: tokens(executor.output_tokens)
        )
      ],
      " · "
    ) <> board_line(executor)
  end

  defp facts(_source, executor) do
    Enum.join(
      [
        sessions_text(executor.executions),
        requests_text(executor.requests),
        gettext("%{tokens} output tokens", tokens: tokens(executor.output_tokens))
      ],
      " · "
    ) <> board_line(executor)
  end

  defp sessions_text(count),
    do: ngettext("%{count} session", "%{count} sessions", count, count: count)

  defp requests_text(count),
    do: ngettext("%{count} request", "%{count} requests", count, count: count)

  defp board_line(executor) do
    direct = Enum.sum(Enum.map(executor.direct, &elem(&1, 1)))
    outside = Enum.sum(Enum.map(executor.outside, &elem(&1, 1)))
    names = Enum.map_join(Enum.take(executor.outside, 4), ", ", &elem(&1, 0))
    more = length(executor.outside) - 4

    parts =
      []
      |> maybe_part(
        direct > 0,
        ngettext(
          "%{count} execution from the board",
          "%{count} executions from the board",
          direct
        ),
        count: direct
      )
      |> maybe_part(
        outside > 0 and names != "",
        gettext("the others were: %{names}", names: names),
        names: names
      )
      |> maybe_part(more > 0, gettext("and %{count} more", count: more), count: more)
      |> maybe_part(
        executor.unknown > 0,
        gettext("%{count} without a repository", count: executor.unknown),
        count: executor.unknown
      )

    case parts do
      [] -> ""
      parts -> " · " <> Enum.join(parts, " · ")
    end
  end

  defp maybe_part(parts, true, text, _opts), do: parts ++ [text]
  defp maybe_part(parts, _false, _text, _opts), do: parts

  defp quota_percent(%{quota: %{used_percent: percent}}) when is_number(percent),
    do: round(percent)

  defp quota_percent(_executor), do: 0

  defp quota_note(%{quota: %{used_percent: percent}}) when is_number(percent) and percent >= 80 do
    gettext(
      "Close to the end of the week. New dispatches to Codex stop when only the reserve is left."
    )
  end

  defp quota_note(%{quota: nil}),
    do: gettext("No recent quota reading. The board does not treat it as zero.")

  defp quota_note(_executor),
    do: gettext("Measured within the weekly window of the ChatGPT plan.")

  defp bars(daily, source, days) do
    today = Date.utc_today()
    by_day = for row <- daily, row.source == source, into: %{}, do: {row.day, row}

    days
    |> then(fn count -> Enum.map(0..(count - 1), &Date.add(today, -&1)) end)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {day, index} -> {day, Map.get(by_day, day), index} end)
  end

  defp bar_state(nil, _source), do: "is-unknown"

  defp bar_state(row, source),
    do: if(cost_micros(row, source), do: "is-known", else: "is-unknown")

  defp bar_height(row, source, daily) do
    values = for row <- daily, row.source == source, value = cost_micros(row, source), do: value
    max = Enum.max(values, fn -> 1 end)
    value = cost_micros(row, source) || 0
    if max <= 0, do: 0, else: round(value / max * 100)
  end

  defp cost_micros(%{cost: %{micros: micros}}, _source) when is_integer(micros), do: micros
  defp cost_micros(_row, _source), do: nil

  defp bar_label(day, index, days) do
    cond do
      # A UTC day, not the owner's today: in the evening in Brazil it is tomorrow.
      day == Date.utc_today() -> Calendar.strftime(day, "%d/%m")
      days == 7 -> short_weekday(day)
      rem(index, 5) == 0 -> Calendar.strftime(day, "%d")
      true -> ""
    end
  end

  defp short_weekday(day) do
    case Date.day_of_week(day) do
      1 -> gettext("Mon")
      2 -> gettext("Tue")
      3 -> gettext("Wed")
      4 -> gettext("Thu")
      5 -> gettext("Fri")
      6 -> gettext("Sat")
      7 -> gettext("Sun")
    end
  end

  defp day_title(day, nil, _source), do: gettext("%{date}: unknown", date: utc_date(day))
  defp day_title(day, _row, _source), do: utc_date(day)

  defp utc_date(day), do: "#{Date.to_iso8601(day)} UTC"

  defp ai_tone(:logged_in), do: "is-stale"
  defp ai_tone(_status), do: "is-faint"

  defp ai_label(:logged_in), do: gettext("connection not verified")
  defp ai_label(:not_configured), do: gettext("not configured")
  defp ai_label(:rehearsal), do: gettext("rehearsal · local fixtures")
  defp ai_label(_status), do: gettext("unknown")

  defp ai_tokens(call) do
    if is_integer(call.input_tokens) and is_integer(call.output_tokens),
      do: tokens(call.input_tokens + call.output_tokens),
      else: "—"
  end

  defp ai_cost(nil), do: "—"

  defp ai_cost(micros) when is_integer(micros) and micros > 0,
    do: AgentBoardWeb.Numbers.usd_exact(micros)

  defp ai_cost(_micros), do: "—"

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

  defp latency_text(nil), do: "—"
  defp latency_text(ms) when is_integer(ms), do: AgentBoardWeb.Numbers.grouped(ms) <> " ms"

  defp ago(nil), do: "—"
  defp ago(at), do: Time.ago(Time.age_seconds(at, DateTime.utc_now()))

  defp dirty_text(0, _labels), do: gettext("No unsaved changes")

  defp dirty_text(count, labels),
    do:
      ngettext("%{count} unsaved change: %{labels}", "%{count} unsaved changes: %{labels}", count,
        count: count,
        labels: labels
      )

  defp label("monthly_usd"), do: gettext("Monthly cap")
  defp label("task_usd"), do: gettext("Task cap")
  defp label("timeout_minutes"), do: gettext("Time per task")
  defp label("reserve_percent"), do: gettext("Quota reserve")
  defp label("claude_model"), do: gettext("Claude Code model")
  defp label("codex_model"), do: gettext("Codex model")
  defp label(key), do: key

  defp tokens(0), do: "—"
  defp tokens(n) when n >= 1_000_000, do: "#{float(n / 1_000_000)}M"
  defp tokens(n) when n >= 1000, do: "#{float(n / 1000)}k"
  defp tokens(n), do: number(n)

  defp float(value), do: AgentBoardWeb.Numbers.decimal(value, 1)

  defp percent(value) when is_float(value),
    do: value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")

  defp percent(value), do: to_string(value)

  # The gate's reason reads after a colon; alone in a paragraph it opens a sentence.
  defp sentence(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  defp money(value) when is_float(value), do: money_micros(round(value * 1_000_000))

  # From a thousand dollars up the cents are noise.
  defp money_micros(micros),
    do: AgentBoardWeb.Numbers.usd(micros, cents: micros < 1_000_000_000)

  @doc "Who answers the board's own calls, as the Execution intro says it (`AI.answering/0`)."
  def ai_line(%{provider: nil}),
    do:
      gettext(
        "No AI key: the board's own calls answer an error. Set one in .env.local; AI and setup says which."
      )

  def ai_line(%{provider: :rehearsal}),
    do: gettext("The board answers in rehearsal, from local fixtures: no key, no cost.")

  def ai_line(%{provider: provider, model: model, fallbacks: fallbacks}) do
    {:ok, %{label: label}} = AgentBoard.AI.Providers.fetch(provider)

    uses =
      gettext("The board uses %{provider} (%{model}) to answer, suggest unblocks and speak",
        provider: label,
        model: model
      )

    others =
      case fallbacks do
        [] ->
          ""

        _ ->
          "; " <>
            gettext("%{others} if it fails",
              others: Enum.map_join(fallbacks, ", ", &provider_label/1)
            )
      end

    uses <> others <> ". " <> gettext("Costs are estimated by the model price.")
  end

  defp provider_label(id) do
    case AgentBoard.AI.Providers.fetch(id) do
      {:ok, %{label: label}} -> label
      :error -> to_string(id)
    end
  end
end
