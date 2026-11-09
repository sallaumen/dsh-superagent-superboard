defmodule AgentBoardWeb.Components.SystemPanelTest do
  @moduledoc "The manual update explains the restart before it happens."
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AgentBoardWeb.Components.SystemPanel

  test "a behind checkout warns that the restart is manual" do
    html =
      render_component(&SystemPanel.version_panel/1, %{
        version: %{
          state: :behind,
          behind: 1,
          served: "abc1234",
          available: "def5678",
          dirty: false
        }
      })

    assert html =~ "Atualizar e reiniciar"
    assert html =~ "version-restart-warning"
    assert html =~ "é manual"
    assert html =~ "agentes em execução podem ser"
    assert html =~ ~s(aria-describedby="version-restart-warning")
  end

  test "a downloaded checkout asks for a restart instead of another update" do
    html =
      render_component(&SystemPanel.version_panel/1, %{
        version: %{
          state: :restart,
          behind: 0,
          served: "abc1234",
          available: "def5678",
          dirty: false
        }
      })

    assert html =~ "Reiniciar para aplicar"
    assert html =~ "O código novo já está no checkout"
    refute html =~ "Atualizar e reiniciar"
  end

  test "the staged pipeline renders its steps" do
    html =
      render_component(&SystemPanel.version_panel/1, %{
        version: %{
          state: :behind,
          behind: 1,
          served: "abc1234",
          available: "def5678",
          dirty: false
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

  test "an up-to-date checkout has no update or warning" do
    html =
      render_component(&SystemPanel.version_panel/1, %{
        version: %{
          state: :up_to_date,
          behind: 0,
          served: "abc1234",
          available: "abc1234",
          dirty: false
        }
      })

    refute html =~ "version-restart-warning"
    refute html =~ "Atualizar e reiniciar"
  end
end
