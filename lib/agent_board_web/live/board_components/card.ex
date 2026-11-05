defmodule AgentBoardWeb.BoardComponents.Card do
  @moduledoc "The board's card region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "mb-2 border border-base-content/10 border-l-2 bg-base-200 px-3 py-2 transition-colors hover:bg-base-300",
        @state == :running && "border-l-warning",
        @state == :ready && "border-l-info",
        @state == :blocked && "border-l-error",
        @state == :merged && "border-l-success",
        @state == :queued && "border-l-base-content/50"
      ]}
    >
      <a
        :if={@item.url}
        href={@item.url}
        target="_blank"
        rel="noopener noreferrer"
        class="block break-words text-sm font-medium hover:underline"
      >
        {@item.title}
      </a>
      <span :if={is_nil(@item.url)} class="block break-words text-sm font-medium">{@item.title}</span>
      <span
        :if={review_badge(@item)}
        class={["ml-2 text-[11px] uppercase", review_badge_class(@item)]}
      >
        {review_badge(@item)}
      </span>
      <span
        :if={checks_badge(@item)}
        class={["ml-2 text-[11px] uppercase", checks_badge_class(@item)]}
      >
        {checks_badge(@item)}
      </span>
      <span :if={@item.number} class="ml-2 text-[11px] tabular-nums text-base-content/75">
        #{@item.number}
      </span>

      <div
        :if={@state in [:running, :ready, :blocked, :queued]}
        class="mt-2 flex gap-1 text-[11px]"
      >
        <button
          phx-click={JS.push_focus() |> JS.push("open")}
          phx-value-id={@item.id}
          aria-label={"Open task: " <> @item.title}
          class="rounded-sm border border-base-content/15 px-2 py-1 hover:bg-base-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
        >Open</button>
        <button
          phx-click="act"
          phx-value-id={@item.id}
          phx-value-action="stop"
          phx-disable-with="Stopping…"
          title="Closes the GitHub issue and stops this task"
          aria-label={"Stop task: " <> @item.title}
          class="rounded-sm border border-base-content/15 px-2 py-1 hover:bg-base-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
        >Stop</button>
        <button
          phx-click="act"
          phx-value-id={@item.id}
          phx-value-action="archive"
          phx-disable-with="Archiving…"
          title="Hides this task from the board; keeps its history"
          aria-label={"Archive task: " <> @item.title}
          class="rounded-sm border border-base-content/15 px-2 py-1 hover:bg-base-300 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
        >
          Archive
        </button>
      </div>
    </div>
    """
  end
end
