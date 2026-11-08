defmodule AgentBoardWeb.BoardComponents.Markup do
  @moduledoc "A tiny, safe subset of inline markup for the board's reasons."
  use AgentBoardWeb, :html

  attr :text, :string, required: true
  attr :class, :string, default: nil

  def markup(assigns) do
    assigns = assign(assigns, :parts, parts(assigns.text))

    ~H"<span class={@class}><strong :for={part <- @parts} :if={part.kind == :strong}>{part.text}</strong><code
  :for={part <- @parts}
  :if={part.kind == :code}
>{part.text}</code><span :for={part <- @parts} :if={part.kind == :text}>{part.text}</span></span>"
  end

  @doc "Split `**strong**` and `` `code` `` into escaped text parts; no HTML is accepted."
  def parts(nil), do: []

  def parts(text) do
    ~r/(\*\*[^*]+\*\*|`[^`]+`)/
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(fn part ->
      cond do
        String.starts_with?(part, "**") ->
          %{kind: :strong, text: part |> String.trim_leading("**") |> String.trim_trailing("**")}

        String.starts_with?(part, "`") ->
          %{kind: :code, text: part |> String.trim_leading("`") |> String.trim_trailing("`")}

        true ->
          %{kind: :text, text: part}
      end
    end)
  end
end
