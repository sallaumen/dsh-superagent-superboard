defmodule AgentBoardWeb.BoardComponents.QueueListTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.BoardComponents.QueueList

  test "the selected button uses the filter key regardless of its position or translated label" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")

    queue = %{
      items: [],
      counts: %{all: 9},
      total: 0,
      hidden: 0,
      filter: :dupes,
      filters: [dupes: 0, all: 9]
    }

    buttons =
      render_component(&QueueList.queue_list/1, queue: queue)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("button[phx-click=filter_queue]")

    assert LazyHTML.attribute(buttons, "phx-value-filter") == ["dupes", "all"]
    assert LazyHTML.attribute(buttons, "aria-pressed") == ["true", "false"]
    assert LazyHTML.text(buttons) =~ "Possíveis repetidas"
  end
end
