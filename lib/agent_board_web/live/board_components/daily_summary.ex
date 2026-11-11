defmodule AgentBoardWeb.BoardComponents.DailySummary do
  @moduledoc """
  The summary of the day under the digest: what was done, what failed and
  still needs the owner, what the board did on its own and what each
  executor spent. It renders the facts stored in the row
  (`AgentBoard.DailySummary.Entry`), never a recomputation; it arrives with
  a broadcast and leaves when dismissed, without motion (`docs/ui-motion.md`:
  data that arrives is not animated). The `DailySummaryVoice` hook asks to
  speak it from a tab the owner has interacted with.
  """
  use AgentBoardWeb, :html

  alias AgentBoardWeb.Time

  @labels %{"deepseek" => "DeepSeek", "claude" => "Claude Code", "codex" => "Codex"}

  attr :entry, :map, required: true
  attr :tz_offset, :integer, default: 0

  def daily_summary(assigns) do
    content = assigns.entry.content

    assigns =
      assign(assigns,
        merged: content["merged"] || %{},
        needs: content["needs"] || %{},
        sync_errors: content["sync_errors"] || 0,
        retries: content["retries"] || %{},
        spend: content["spend"] || []
      )

    ~H"""
    <section
      id="daily-summary"
      class="ab-daily"
      aria-labelledby="daily-summary-title"
      phx-hook="DailySummaryVoice"
      data-id={@entry.id}
      data-spoken={to_string(not is_nil(@entry.spoken_at))}
    >
      <header class="ab-daily__head">
        <h2 id="daily-summary-title">
          {gettext("Daily summary")}
          <small class="ab-daily__scope">{gettext("from the board")}</small>
        </h2>
        <span class="ab-daily__since">
          {gettext("since %{when}",
            when: Time.since_label(@entry.window_start, @tz_offset, @entry.generated_at)
          )}
        </span>
        <button
          id="daily-summary-dismiss"
          type="button"
          class="ab-btn ab-btn--sm ab-daily__dismiss"
          phx-click="dismiss_daily_summary"
          phx-value-id={@entry.id}
          data-daily-dismiss
          aria-label={gettext("Dismiss daily summary")}
        >
          {gettext("Dismiss")}
        </button>
      </header>
      <dl class="ab-daily__rows">
        <div>
          <dt>{gettext("Done")}</dt>
          <dd>
            <span :if={is_integer(@merged["issues"])} class="ab-delivered">
              {AgentBoardWeb.BoardComponents.MergeLog.delivered(@merged["issues"], @merged["issues"])} ·
            </span>
            {merged_text(@merged["count"] || 0)}<.refs items={@merged["items"] || []} />
          </dd>
        </div>
        <div>
          <dt>{gettext("Failures and pending items")}</dt>
          <dd>
            {needs_text(@needs)}<.refs items={@needs["items"] || []} />{sync_text(@sync_errors)}
          </dd>
        </div>
        <div>
          <dt>{gettext("What the board did automatically")}</dt>
          <dd>{retries_text(@retries)}</dd>
        </div>
        <div>
          <dt>{gettext("Spend")}</dt>
          <dd class="ab-daily__spend">
            <span :for={line <- @spend} title={spend_title(line)}>
              {label(line)} <b>{spend_text(line)}</b>
            </span>
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :items, :list, required: true

  defp refs(assigns) do
    ~H"""
    <span :if={@items != []} class="ab-daily__refs" phx-no-format> (<%= for {item, i} <- Enum.with_index(@items) do %><%= if i > 0 do %>, <% end %><a href={item["url"]} title={"#{item["repo"]}: #{item["title"]}"} target="_blank" rel="noopener noreferrer">#{item["number"]}</a><% end %>)</span>
    """
  end

  defp merged_text(0), do: gettext("No PRs merged")
  defp merged_text(n), do: ngettext("%{count} PR merged", "%{count} PRs merged", n)

  defp needs_text(needs) do
    blocked = needs["blocked"] || 0
    waiting = needs["waiting"] || 0

    case {blocked, waiting} do
      {0, 0} ->
        gettext("Nothing waiting for you")

      {b, 0} ->
        ngettext("%{count} blocked", "%{count} blocked", b)

      {0, w} ->
        ngettext("%{count} waiting for you", "%{count} waiting for you", w)

      {b, w} ->
        ngettext(
          "%{blocked} blocked, %{waiting} waiting for you",
          "%{blocked} blocked, %{waiting} waiting for you",
          b,
          blocked: b,
          waiting: w
        )
    end
  end

  defp sync_text(n) when is_integer(n) and n > 0,
    do: "; " <> ngettext("sync failed %{count} time", "sync failed %{count} times", n)

  defp sync_text(_n), do: nil

  defp retries_text(%{"sent" => sent} = retries) when is_integer(sent) and sent > 0 do
    tasks = retries["tasks"] || 0
    refused = retries["not_accepted"] || 0

    head =
      ngettext("%{count} new automatic retry", "%{count} new automatic retries", sent) <>
        if(tasks > 1,
          do: ngettext(" across %{count} task", " across %{count} tasks", tasks),
          else: ""
        )

    if refused > 0,
      do:
        head <>
          "; " <> ngettext("%{count} was not accepted", "%{count} were not accepted", refused),
      else: head
  end

  defp retries_text(_retries), do: gettext("No new automatic attempt")

  defp label(line), do: Map.get(@labels, line["executor"], line["executor"])

  defp spend_text(%{"status" => "measured", "currency" => "quota"} = line) do
    gettext("%{percent}% of weekly quota", percent: percent(line["percent"]))
  end

  defp spend_text(%{"status" => "measured", "micros" => micros} = line) when is_integer(micros) do
    amount =
      cond do
        micros < 5_000 -> gettext("less than USD 0.01")
        line["complete"] == false -> "≥ #{dollars(micros)}"
        true -> "≈ #{dollars(micros)}"
      end

    list_mark(line, amount)
  end

  defp spend_text(%{"status" => "none"}), do: gettext("did not run")
  defp spend_text(_line), do: gettext("unknown")

  defp list_mark(%{"reference" => "list"}, amount),
    do: gettext("%{amount} (list price)", amount: amount)

  defp list_mark(_line, amount), do: amount

  defp percent(value) when is_float(value),
    do: value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")

  defp percent(value), do: to_string(value)

  defp spend_title(%{"status" => "measured", "currency" => "quota"} = line) do
    gettext("ChatGPT plan weekly quota: %{percent}% used.", percent: percent(line["percent"])) <>
      if(line["resets_at"],
        do: gettext(" Resets at %{time}.", time: line["resets_at"]),
        else: gettext(" No reset time in the reading.")
      ) <>
      gettext(" No USD value for Codex.")
  end

  defp spend_title(%{"status" => "measured"} = line) do
    requests = line["requests"]
    models = Enum.join(line["models"] || [], ", ")

    prefix =
      if line["reference"] == "list",
        do:
          gettext(
            "List price for Claude Max; this is a reference, not an invoice, and the actual quota is unknown"
          ),
        else: gettext("Estimated at list price")

    prefix <>
      if(is_integer(requests), do: gettext(", %{count} calls", count: requests), else: "") <>
      if(models != "", do: " (#{models})", else: "") <>
      if(line["complete"] == false,
        do: gettext("; an unpriced token type makes this a minimum"),
        else: ""
      )
  end

  defp spend_title(%{"status" => "none"}), do: gettext("No calls in the summary window")

  defp spend_title(%{"reason" => "no_source"}),
    do: gettext("No usage source: the board does not yet read this executor")

  defp spend_title(%{"reason" => "no_quota"}),
    do: gettext("No Codex weekly quota reading")

  defp spend_title(%{"reason" => "zstd_missing"}),
    do: gettext("zstd not in PATH; transcripts cannot be read")

  defp spend_title(%{"reason" => "no_price"}),
    do: gettext("The model used has no price in the board table")

  defp spend_title(_line), do: gettext("Transcripts could not be read")

  defp dollars(micros), do: AgentBoardWeb.Numbers.usd(micros)
end
