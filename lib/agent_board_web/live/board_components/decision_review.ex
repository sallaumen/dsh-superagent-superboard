defmodule AgentBoardWeb.BoardComponents.DecisionReview do
  @moduledoc "An owner's follow-up on a specific historical agent comment in the issue conversation."
  use AgentBoardWeb, :live_component

  alias AgentBoard.{Actions, GitHub}
  alias AgentBoardWeb.Locale

  @max_reason 2000
  @max_excerpt 420

  def available?(task, %{kind: "agent", github_id: id, task_id: task_id})
      when is_integer(id) and id > 0 do
    task_id == task.id and task.kind == "issue" and is_integer(task.number) and
      not task.stopped and match?(%{owner: owner} when is_binary(owner), task.repository)
  end

  def available?(_, _), do: false

  @impl true
  def mount(socket), do: {:ok, assign(socket, step: :closed, reason: "", error: nil, source: nil)}

  @impl true
  def handle_event("open", _, %{assigns: %{step: :closed}} = socket) do
    %{task: task, comment: c, text: body} = socket.assigns
    repo = task.repository

    url =
      "https://github.com/#{repo.owner}/#{repo.name}/issues/#{task.number}#issuecomment-#{c.github_id}"

    snippet =
      body
      |> String.replace(~r/^This is by an automated agent, not a human\.\s*/i, "")
      |> String.trim()

    excerpt =
      if String.length(snippet) > @max_excerpt,
        do: String.slice(snippet, 0, @max_excerpt) <> "…",
        else: snippet

    {:noreply, assign(socket, step: :edit, source: %{url: url, excerpt: excerpt}, error: nil)}
  end

  def handle_event("change", %{"reason" => reason}, %{assigns: %{step: :edit}} = socket),
    do: {:noreply, assign(socket, reason: reason, error: nil)}

  def handle_event("cancel", _, %{assigns: %{step: :edit}} = socket),
    do: {:noreply, assign(socket, step: :closed, reason: "", error: nil, source: nil)}

  def handle_event("submit", %{"reason" => reason}, %{assigns: %{step: :edit}} = socket) do
    reason = String.trim(reason)

    if String.length(reason) in 1..@max_reason do
      %{task: task, source: source} = socket.assigns

      quote =
        source.excerpt
        |> String.replace("@", "＠")
        |> String.split("\n")
        |> Enum.map_join("\n", &("> " <> &1))

      message =
        Enum.join(
          [
            gettext("Decision review"),
            source.url,
            quote,
            gettext("Reason for review:") <> "\n" <> reason,
            gettext(
              "Reassess the original decision against the evidence then and now. Reply here with what you would keep or change and why. This requests a review only; do not change code or open a PR."
            )
          ],
          "\n\n"
        )

      params = %{task: task, question: message, client: GitHub.client()}
      language = Locale.language()
      phrase = Actions.phrase(:ask_task, params, language)

      {:noreply,
       socket
       |> assign(step: :sending, reason: reason, error: nil)
       |> start_async(:post, fn ->
         Actions.run(:ask_task, params, Actions.owner(:ui), confirm: phrase, language: language)
       end)}
    else
      {:noreply,
       assign(socket, reason: reason, error: gettext("Enter a reason (up to 2,000 characters)."))}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:post, {:ok, {:ok, _comment}}, socket),
    do: {:noreply, assign(socket, step: :sent, reason: "")}

  def handle_async(:post, _failed, socket),
    do:
      {:noreply,
       assign(socket,
         step: :edit,
         error: gettext("Could not confirm publication. Check the issue before sending again.")
       )}

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ab-decision-review">
      <button
        :if={@step == :closed}
        type="button"
        class="ab-btn ab-btn--sm ab-btn--quiet"
        phx-click="open"
        phx-target={@myself}
      >{gettext("Review this decision")}</button>
      <form
        :if={@step in [:edit, :sending]}
        id={@id <> "-form"}
        phx-change="change"
        phx-submit="submit"
        phx-target={@myself}
      >
        <a href={@source.url} target="_blank" rel="noopener">{gettext("Original comment")}</a>
        <blockquote>{@source.excerpt}</blockquote>
        <label for={@id <> "-reason"}>{gettext("What should the agent reconsider?")}</label>
        <textarea
          id={@id <> "-reason"}
          name="reason"
          phx-mounted={Phoenix.LiveView.JS.focus()}
          rows="3"
          maxlength="2000"
          required
          disabled={@step == :sending}
        >{@reason}</textarea>
        <small>{gettext(
          "Posts a review request on issue #%{number}. Code changes require a separate request.",
          number: @task.number
        )}</small>
        <span :if={@error} role="alert">{@error}</span>
        <div>
          <button
            type="submit"
            class="ab-btn ab-btn--sm ab-btn--primary"
            disabled={@step == :sending}
            phx-disable-with={gettext("Sending…")}
          >{gettext("Request review")}</button>
          <button
            type="button"
            phx-click="cancel"
            phx-target={@myself}
            class="ab-btn ab-btn--sm ab-btn--quiet"
            disabled={@step == :sending}
          >{gettext("Cancel")}</button>
        </div>
      </form>
      <span :if={@step == :sent} role="status">{gettext("Review requested on issue #%{number}.",
        number: @task.number
      )}</span>
    </div>
    """
  end
end
