defmodule AgentBoardWeb.Components.SystemPanelTest do
  @moduledoc "The version card's states and buttons, without a network read."
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.Components.SystemPanel

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
    :ok
  end

  defp card(version), do: render_component(&SystemPanel.version_panel/1, %{version: version})

  test "a board behind main lists the commits and offers update and restart" do
    version = %{
      state: :behind,
      served: "a7adfab",
      available: "a9aef67",
      behind: 1,
      dirty: false,
      commits: [%{sha: "a9aef67", title: "Call the agent on a split's tasks (#467)", pr: 467}]
    }

    html = card(version)

    assert html =~ "Tem versão nova na main"
    assert html =~ "a9aef67"
    assert html =~ "Call the agent"
    assert html =~ "#467"
    assert html =~ "Só reiniciar"
    assert html =~ "Atualizar e reiniciar"
    assert html =~ "Atualizar reinicia o board"
    assert html =~ "Nada atualiza sozinho"
    refute html =~ "Reiniciar para aplicar"
  end

  test "a downloaded checkout asks for the restart, not the update" do
    version = %{
      state: :restart,
      served: "a7adfab",
      available: "a9aef67",
      behind: 0,
      dirty: false,
      commits: [%{sha: "a9aef67", title: "Call the agent", pr: 467}]
    }

    html = card(version)

    assert html =~ "Código novo baixado; reinício pendente"
    assert html =~ "Reiniciar para aplicar"
    refute html =~ "Atualizar e reiniciar"
  end

  test "an up-to-date board only offers a restart" do
    html =
      card(%{
        state: :up_to_date,
        served: "a7adfab",
        available: "a7adfab",
        behind: 0,
        dirty: false,
        commits: []
      })

    assert html =~ "Em dia com a main"
    assert html =~ "Só reiniciar"
    refute html =~ "Atualizar e reiniciar"
    refute html =~ "Atualizar reinicia o board"
    refute html =~ "Tem versão nova"
  end

  test "the staged pipeline renders its steps" do
    html =
      render_component(&SystemPanel.version_panel/1, %{
        version: %{
          state: :behind,
          behind: 1,
          served: "abc1234",
          available: "def5678",
          dirty: false,
          commits: []
        },
        busy: true,
        progress: [
          %{id: :fetch, state: :done, label: "Buscando a main"},
          %{id: :compile, state: :running, label: "Compilando o build novo"}
        ]
      })

    assert html =~ "update-progress"
    assert html =~ "Buscando a main"
    assert html =~ "Compilando o build novo"
    assert html =~ ~s(data-state="done")
    assert html =~ ~s(data-state="running")
  end
end
