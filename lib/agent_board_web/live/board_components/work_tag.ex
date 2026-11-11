defmodule AgentBoardWeb.BoardComponents.WorkTag do
  @moduledoc """
  The split's classification of a task, in the board's words: where the
  work lands and its size ("UI · P"). A kind or a size the split did not
  give is left out; with neither, nothing renders.
  """
  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  @work_types %{
    "ui" => "UI",
    "backend" => "backend",
    "docs" => "docs",
    "bug" => "bug",
    "research" => "research",
    "infra" => "infra"
  }

  @doc "The kind of work as the board says it; nil when unknown."
  def work_type_label("research"), do: gettext("research")
  def work_type_label(work_type), do: Map.get(@work_types, work_type)

  @doc "The size as the board says it (P, M, G); nil when unknown."
  def size_label("S"), do: pgettext("size", "S")
  def size_label("M"), do: pgettext("size", "M")
  def size_label("L"), do: pgettext("size", "L")
  def size_label(_size), do: nil

  attr :work_type, :string, default: nil
  attr :size, :string, default: nil
  attr :class, :string, default: "ab-meta"

  def work_tag(assigns) do
    assigns =
      assigns
      |> assign(:type_label, work_type_label(assigns.work_type))
      |> assign(:size, size_pair(assigns.size))

    ~H"""
    <span
      :if={@type_label || @size}
      class={["ab-work", @class]}
      title={gettext("Type and size proposed by the split")}
    >
      <span :if={@type_label}>{@type_label}</span>
      <span :if={@type_label && @size} aria-hidden="true">·</span>
      <span :if={@size}>
        <span aria-hidden="true">{elem(@size, 0)}</span><span class="ab-sr">{gettext("task %{size}",
          size: elem(@size, 1)
        )}</span>
      </span>
    </span>
    """
  end

  defp size_pair("S"), do: {size_label("S"), gettext("small")}
  defp size_pair("M"), do: {size_label("M"), gettext("medium")}
  defp size_pair("L"), do: {size_label("L"), gettext("large")}
  defp size_pair(_size), do: nil
end
