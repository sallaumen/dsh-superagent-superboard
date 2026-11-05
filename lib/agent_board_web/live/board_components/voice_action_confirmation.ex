defmodule AgentBoardWeb.BoardComponents.VoiceActionConfirmation do
  @moduledoc "Review of an explicit voice task action before it can change state."
  use Phoenix.Component

  attr :intent, :map, required: true

  def review(assigns) do
    ~H"""
    <section class="voice-action-review" aria-labelledby="voice-action-heading">
      <p class="voice-action-eyebrow">Confirmation required</p>
      <h3 id="voice-action-heading">{label(@intent.action)} task #{@intent.number}?</h3>
      <p class="voice-action-target">{@intent.title}</p>
      <p class="voice-action-repository">{@intent.repository}</p>
      <p class="voice-action-effect">{effect(@intent.action)}</p>
      <div class="voice-action-buttons">
        <button type="button" phx-click="voice_cancel_action">Cancel</button>
        <button
          type="button"
          phx-click="voice_confirm_action"
          phx-disable-with="Working…"
          class="voice-action-confirm"
        >Confirm {String.downcase(label(@intent.action))}</button>
      </div>
    </section>
    """
  end

  defp label(:stop), do: "Stop"
  defp label(:archive), do: "Archive"

  defp effect(:stop), do: "Closes the GitHub issue and stops this task."
  defp effect(:archive), do: "Hides this task from the board and keeps its history."
end
