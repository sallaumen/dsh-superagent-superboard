defmodule AgentBoardWeb.BoardComponents.Markup do
  @moduledoc """
  A tiny, safe subset of inline markup: strong, code and, where a caller asks
  for it, links. No HTML is accepted; a link is only ever http or https.
  """
  use AgentBoardWeb, :html

  alias AgentBoard.Board.Attachments

  attr :text, :string, required: true
  attr :class, :string, default: nil
  attr :links, :boolean, default: false

  def markup(assigns) do
    parts = parts(assigns.text)
    assigns = assign(assigns, :parts, if(assigns.links, do: link_parts(parts), else: parts))

    # One line on purpose: the text is shown with its own white space.
    ~H|<span class={@class} phx-no-format><%= for part <- @parts do %><strong :if={part.kind == :strong}>{part.text}</strong><code :if={part.kind == :code}>{part.text}</code><a :if={part.kind == :link} href={part.href} target="_blank" rel="noopener noreferrer">{part.text}</a><span :if={part.kind == :text}>{part.text}</span><% end %></span>|
  end

  # `[words](https://…)`, `![alt](https://…)` and a bare address. An image is
  # a link too: the page loads images only from the board itself.
  @link ~r/!?\[([^\]\n]*)\]\((https?:\/\/[^\s)]+)\)|https?:\/\/[^\s<>"']*[^\s<>"'.,;:!?)\]]/

  @doc "Split the text parts once more into links and the words around them."
  def link_parts(parts) do
    Enum.flat_map(parts, fn
      %{kind: :text, text: text} ->
        @link
        |> Regex.split(text, include_captures: true, trim: true)
        |> Enum.map(&link_part/1)

      part ->
        [part]
    end)
  end

  defp link_part(piece) do
    case Regex.run(@link, piece) do
      [^piece, label, href] ->
        %{kind: :link, href: href, text: if(label == "", do: href, else: label)}

      [^piece] ->
        %{kind: :link, href: piece, text: address_text(piece)}

      _words ->
        %{kind: :text, text: piece}
    end
  end

  # A stored file's address is 64 characters of hash; its name says the same.
  defp address_text(href) do
    case Attachments.in_body(href) do
      [%{name: name}] -> name
      _other -> href
    end
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
