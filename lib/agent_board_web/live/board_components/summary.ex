defmodule AgentBoardWeb.BoardComponents.Summary do
  @moduledoc "The one-sentence digest at the top of the board."
  use AgentBoardWeb, :html

  attr :digest, :map, default: nil

  def summary(assigns) do
    ~H"""
    <p :if={@digest} class="ab-digest" phx-no-format>{@digest.prefix}<%= for segment <- @digest.segments do %><%= cond do %><% segment[:task_id] -> %><button type="button" class={"ab-digest__link is-#{segment.role}"} phx-click="open" phx-value-id={segment.task_id} data-panel-trigger="conversation">{segment.text}</button><% segment[:url] -> %><a class={"ab-digest__link is-#{segment.role}"} href={segment.url} target="_blank" rel="noopener noreferrer">{segment.text}</a><% true -> %><span class={"is-#{segment.role}"}>{segment.text}</span><% end %><% end %>{@digest.suffix}</p>
    """
  end
end
