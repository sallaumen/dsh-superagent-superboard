defmodule AgentBoardWeb.BoardComponents.Settings.Execution do
  @moduledoc """
  Settings → Execution: the global pause, each executor's limits and who
  answers the board's own AI calls. What they spent is in Settings → Costs.

  The controls are a draft of the board settings. Saving writes one
  `change_setting` action per key, the same registry the voice and the API
  use. Executors are never summed.
  """
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]

  alias AgentBoard.{Actions, AI, Runners}
  alias AgentBoard.AI.Providers
  @draft_keys ~w(monthly_usd task_usd timeout_minutes reserve_percent claude_model codex_model)
  @sources ["claude_code", "codex", "dsh"]

  attr :active, :boolean, default: false
  attr :dispatch_paused, :boolean, default: false
  attr :tickets, :list, default: []
  attr :ai_status, :any, default: :unknown
  attr :parent, :any, default: nil
  attr :tz_offset, :integer, default: 0

  # The settings menu is on every page, so this mounts on every load: the
  # snapshot (which prices the month) is read when the section opens.
  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       sources: @sources,
       snapshot: nil,
       saved: %{},
       draft: %{},
       dirty: [],
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
       |> assign_dirty()}
    else
      {:ok, socket}
    end
  end

  @impl true
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
        <button
          id="execution-costs-link"
          type="button"
          class="ab-link"
          phx-click="select_section"
          phx-value-section="costs"
          phx-target={@parent}
        >{gettext("What they spent is in Costs")}</button>
      </div>

      <form
        id="execution-settings-form"
        phx-change="change"
        phx-submit="save"
        phx-target={@myself}
        phx-auto-recover="ignore"
        class="ab-execution__form"
      >
        <div :if={@snapshot} class="ab-execution__executors">
          <article :for={source <- @sources} id={"executor-" <> source} class="ab-executor">
            <.executor_block source={source} draft={@draft} snapshot={@snapshot} parent={@parent} />
          </article>
        </div>

        <section class="ab-execution__ai" aria-labelledby="execution-ai-title">
          <header class="ab-execution__ai-head">
            <div>
              <h4 id="execution-ai-title">{gettext("The board's own AI calls")}</h4>
              <p class="ab-meta">
                {ai_line(AI.answering())}
              </p>
            </div>
            <span class={["ab-execution__ai-state", ai_tone(@ai_status)]}>
              <.glyph kind={:stale} />{ai_label(@ai_status)}
            </span>
          </header>

          <button
            id="execution-calls-link"
            type="button"
            class="ab-link"
            phx-click="select_section"
            phx-value-section="costs"
            phx-target={@parent}
          >{gettext("Each call, with its tokens and cost, is in Costs")}</button>
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
  attr :draft, :map, required: true
  attr :snapshot, :map, required: true
  attr :parent, :any, default: nil

  defp executor_block(assigns) do
    ~H"""
    <header class="ab-executor__head">
      <h5>{label_for(@source)}</h5>
    </header>

    <div class="ab-executor__body">
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

  defp label_for("claude_code"), do: "Claude Code"
  defp label_for("codex"), do: "Codex"
  defp label_for("dsh"), do: "DeepSeek"
  defp label_for(source), do: source

  defp ai_tone(:logged_in), do: "is-stale"
  defp ai_tone(_status), do: "is-faint"

  defp ai_label(:logged_in), do: gettext("connection not verified")
  defp ai_label(:not_configured), do: gettext("not configured")
  defp ai_label(:rehearsal), do: gettext("rehearsal · local fixtures")
  defp ai_label(_status), do: gettext("unknown")

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
    {:ok, %{label: label}} = Providers.fetch(provider)

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
    case Providers.fetch(id) do
      {:ok, %{label: label}} -> label
      :error -> to_string(id)
    end
  end
end
