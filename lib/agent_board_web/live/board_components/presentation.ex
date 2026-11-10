defmodule AgentBoardWeb.BoardComponents.Presentation do
  @moduledoc "Formatting of stored board data; no reads or actions."
  use Gettext, backend: AgentBoardWeb.Gettext

  def time(nil), do: ""

  def time(dt) do
    dt |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
  end

  def review_badge(%{review_state: state})
      when state in ["approved", "changes_requested", "pending"] do
    case state do
      "approved" -> gettext("approved")
      "changes_requested" -> gettext("changes requested")
      "pending" -> gettext("review pending")
    end
  end

  # "none" is a real answer: the pull has no reviews. Saying it is more honest
  # than hiding the badge and letting the reader guess.
  def review_badge(%{review_state: "none"}), do: gettext("no review")
  def review_badge(_), do: nil

  def review_badge_class(%{review_state: "approved"}), do: "text-success"
  def review_badge_class(%{review_state: "changes_requested"}), do: "text-error"
  def review_badge_class(_), do: "text-base-content/75"

  def checks_badge(%{checks_state: "failure", checks_failed: name})
      when is_binary(name) and name != "",
      do: gettext("ci failed: %{name}", name: name)

  def checks_badge(%{checks_state: "none"}), do: gettext("no ci")

  def checks_badge(%{checks_state: state}) when state in ["success", "failure", "pending"] do
    case state do
      "success" -> gettext("ci passed")
      "failure" -> gettext("ci failed")
      "pending" -> gettext("ci running")
    end
  end

  def checks_badge(_), do: nil

  def checks_badge_class(%{checks_state: "success"}), do: "text-success"
  def checks_badge_class(%{checks_state: "failure"}), do: "text-error"
  def checks_badge_class(_), do: "text-base-content/75"

  def last_sync(nil), do: "no sync yet"

  def last_sync(%{kind: "sync_error"} = event),
    do: "sync failed #{sync_time(event.inserted_at)} · showing saved data"

  def last_sync(sync) do
    errors = sync.payload["errors"] || 0

    suffix =
      case errors do
        0 -> " · clean"
        1 -> " · 1 error"
        n -> " · #{n} errors"
      end

    "synced #{sync_time(sync.inserted_at)}" <> suffix
  end

  def sync_time(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  # Not every non-sync event is a failure: a repository without Issues is a
  # warning, not an error (the pulls still sync).
  def warning?(%{kind: kind}), do: kind == "issues_unavailable"

  # A sync event carries an errors count; the per-item failures (issue_error,
  # pull_error, ...) carry a reason. Both must read as problems.
  def has_errors?(%{kind: kind, payload: payload}) do
    String.ends_with?(kind || "", "_error") or
      (is_integer(payload["errors"]) and payload["errors"] > 0)
  end

  @max_payload 120

  def payload_summary(payload) do
    Enum.map_join(payload, " · ", fn {k, v} -> "#{k}: #{truncate(v)}" end)
  end

  # A network error can carry the whole GitHub body (hundreds of chars) and
  # would wreck the activity column. One line, bounded.
  def truncate(value) when is_binary(value) and byte_size(value) > @max_payload,
    do: String.slice(value, 0, @max_payload) <> "…"

  def truncate(value) when is_binary(value), do: value
  def truncate(value), do: inspect(value)

  def empty_copy(:running), do: "Nenhuma tarefa rodando."
  def empty_copy(:ready), do: gettext("Nothing awaiting review.")
  def empty_copy(:blocked), do: gettext("Nothing blocked.")
  def empty_copy(:merged), do: gettext("No PRs merged yet.")
  def empty_copy(:queued), do: gettext("No tasks in queue.")

  def ai_status_label(:logged_in), do: gettext("Configured · connection not verified")
  def ai_status_label(:not_configured), do: gettext("not configured")
  def ai_status_label(:rehearsal), do: gettext("rehearsal · local fixtures")
  def ai_status_label(status), do: to_string(status)

  def latency(value) when is_integer(value), do: "#{value}ms"
  def latency(_), do: gettext("unknown")

  def token_usage(%{input_tokens: input, output_tokens: output})
      when is_integer(input) and is_integer(output),
      do: "#{input + output} tokens"

  def token_usage(_), do: gettext("unknown")

  # Zero is also stored for old calls and unpriced models, so it is not a
  # trustworthy zero-dollar bill. Keep the stored microdollar precision.
  def estimated_cost(micros) when is_integer(micros) and micros > 0 do
    dollars = div(micros, 1_000_000)

    fraction =
      micros
      |> rem(1_000_000)
      |> Integer.to_string()
      |> String.pad_leading(6, "0")
      |> String.trim_trailing("0")

    if fraction == "", do: "$#{dollars}", else: "$#{dollars}.#{fraction}"
  end

  def estimated_cost(_), do: gettext("unknown")
end
