defmodule AgentBoardWeb.BoardComponents.CancelledBlocker do
  @moduledoc "Keep a cancelled child and the owner's decision visible in the original conversation."
  use AgentBoardWeb, :live_component
  alias AgentBoard.{Actions, BlockerDecisions}
  alias AgentBoardWeb.Locale

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, mode: nil, busy: false, error: nil, reason: "", selected: "")}

  @impl true
  def handle_event("edit", %{"mode" => mode}, socket) when mode in ["replace", "waive"] do
    {:noreply, assign(socket, mode: mode, error: nil, reason: "", selected: "")}
  end

  def handle_event("cancel", _, socket), do: {:noreply, assign(socket, mode: nil, error: nil)}

  def handle_event("change", params, socket),
    do:
      {:noreply,
       assign(socket, reason: params["reason"] || "", selected: params["replacement"] || "")}

  def handle_event(
        "commit",
        %{"reason" => reason} = form,
        %{assigns: %{busy: false, mode: mode}} = socket
      )
      when mode in ["replace", "waive"] do
    %{task: task, child: child, siblings: siblings} = socket.assigns

    chosen =
      Enum.find(siblings, fn s ->
        to_string(s.id) == form["replacement"] && BlockerDecisions.replacement?(task, child, s)
      end)

    params = %{
      task: task,
      child: child,
      choice: mode,
      reason: String.trim(reason),
      replacement_id: chosen && chosen.id,
      replacement_number: chosen && chosen.number
    }

    if String.length(params.reason) in 1..2000 and (mode == "waive" or chosen != nil) do
      lang = Locale.language()
      phrase = Actions.phrase(:resolve_blocker, params, lang)

      {:noreply,
       socket
       |> assign(busy: true)
       |> start_async(:decision, fn ->
         Actions.run(:resolve_blocker, params, Actions.owner(:ui),
           confirm: phrase,
           language: lang
         )
       end)}
    else
      {:noreply,
       assign(socket,
         error:
           gettext(
             "Select an available replacement and enter a reason, or enter a reason to waive."
           )
       )}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}
  @impl true
  def handle_async(:decision, {:ok, {:ok, _}}, socket),
    do: {:noreply, assign(socket, busy: false, mode: nil, error: nil)}

  def handle_async(:decision, {:ok, {:error, :waiver_refused}}, socket),
    do:
      {:noreply,
       assign(socket,
         busy: false,
         error:
           gettext("GitHub refused the comment. The requirement remains blocking. You can retry.")
       )}

  def handle_async(:decision, _, socket),
    do:
      {:noreply,
       assign(socket,
         busy: false,
         mode: nil,
         error: gettext("Decision not confirmed. Check the issue and the current requirement.")
       )}

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :candidates,
        Enum.filter(
          assigns.siblings,
          &BlockerDecisions.replacement?(assigns.task, assigns.child, &1)
        )
      )

    ~H"""
    <section id={@id} class="ab-unblock__form" aria-label={gettext("Evidence requirement")}>
      <a href={@child.url} target="_blank" rel="noopener">#{@child.number} — {@child.title}</a>
      <%= if @child.blocker_decision do %>
        <p><strong>{decision_label(@child.blocker_decision)}</strong></p>
        <p>{@child.blocker_decision["reason"]}</p>
      <% else %>
        <p>
          <strong>{if @child.github_issue_status == "duplicate",
            do: gettext("Closed as duplicate. Evidence still missing."),
            else: gettext("Closed as not planned. Evidence still missing.")}</strong>
        </p>
        <div :if={BlockerDecisions.eligible?(@task, @child) and !@mode} class="ab-unblock__actions">
          <button
            type="button"
            class="ab-btn ab-btn--sm"
            phx-click="edit"
            phx-value-mode="replace"
            phx-target={@myself}
          >{gettext("Replace child")}</button>
          <button
            type="button"
            class="ab-btn ab-btn--sm"
            phx-click="edit"
            phx-value-mode="waive"
            phx-target={@myself}
          >{gettext("Waive requirement")}</button>
        </div>
        <form
          :if={@mode}
          id={@id <> "-form"}
          phx-change="change"
          phx-submit="commit"
          phx-target={@myself}
        >
          <label :if={@mode == "replace"} for={@id <> "-select"}>{gettext(
            "Open child that will provide the evidence"
          )}</label>
          <select :if={@mode == "replace"} id={@id <> "-select"} name="replacement" required>
            <option value="">{gettext("Choose a linked child")}</option>
            <option :for={c <- @candidates} value={c.id} selected={@selected == to_string(c.id)}>
              #{c.number} — {c.title}
            </option>
          </select>
          <p :if={@mode == "replace" and @candidates == []}>
            {gettext("Use Create blocking task below to link a new child, then select it here.")}
          </p>
          <p :if={@mode == "waive"}>
            {gettext(
              "This posts your reason to the original issue. Other requirements remain in force."
            )}
          </p>
          <label for={@id <> "-reason"}>{gettext("Reason for this decision")}</label>
          <textarea id={@id <> "-reason"} name="reason" rows="2" maxlength="2000" required>{@reason}</textarea>
          <div class="ab-unblock__actions">
            <button
              type="submit"
              class="ab-btn ab-btn--sm ab-btn--primary"
              disabled={@busy or (@mode == "replace" and @candidates == [])}
            >{if @mode == "waive", do: gettext("Confirm waiver"), else: gettext("Confirm replacement")}</button>
            <button
              type="button"
              class="ab-btn ab-btn--sm"
              disabled={@busy}
              phx-click="cancel"
              phx-target={@myself}
            >{gettext("Cancel")}</button>
          </div>
        </form>
      <% end %>
      <p :if={@error} role="alert">{@error}</p>
    </section>
    """
  end

  defp decision_label(%{"kind" => "replaced", "replacement" => n}),
    do: gettext("Replaced by #%{number}", number: n)

  defp decision_label(%{"kind" => "waived"}),
    do: gettext("Waived by the owner; no evidence delivered.")

  defp decision_label(_),
    do: gettext("Waiver recorded; publication on the original issue is not confirmed.")
end
