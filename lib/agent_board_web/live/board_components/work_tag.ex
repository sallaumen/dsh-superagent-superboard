defmodule AgentBoardWeb.BoardComponents.WorkTag do
  @moduledoc """
  The split's classification of a task, in the board's words: where the
  work lands and its size ("UI · P"). A kind or a size the split did not
  give is left out; with neither, nothing renders.
  """
  use Phoenix.Component

  @work_types %{
    "ui" => "UI",
    "backend" => "backend",
    "docs" => "docs",
    "bug" => "bug",
    "research" => "pesquisa",
    "infra" => "infra"
  }

  @sizes %{"S" => {"P", "pequena"}, "M" => {"M", "média"}, "L" => {"G", "grande"}}

  @doc "The kind of work as the board says it; nil when unknown."
  def work_type_label(work_type), do: Map.get(@work_types, work_type)

  @doc "The size as the board says it (P, M, G); nil when unknown."
  def size_label(size) do
    case Map.get(@sizes, size) do
      {short, _long} -> short
      nil -> nil
    end
  end

  attr :work_type, :string, default: nil
  attr :size, :string, default: nil
  attr :class, :string, default: "ab-meta"

  def work_tag(assigns) do
    assigns =
      assigns
      |> assign(:type_label, work_type_label(assigns.work_type))
      |> assign(:size, Map.get(@sizes, assigns.size))

    ~H"""
    <span
      :if={@type_label || @size}
      class={["ab-work", @class]}
      title="Tipo e tamanho que a divisão deu"
    >
      <span :if={@type_label}>{@type_label}</span>
      <span :if={@type_label && @size} aria-hidden="true">·</span>
      <span :if={@size}>
        <span aria-hidden="true">{elem(@size, 0)}</span><span class="ab-sr">tarefa {elem(@size, 1)}</span>
      </span>
    </span>
    """
  end
end
