defmodule AgentBoardWeb.UpdateFlowTest do
  @moduledoc "The update button schedules a real restart and never lies about being current."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  defmodule UpdaterStub do
    def pull_changed, do: Application.get_env(:agent_board, :updater_result)
    def restart, do: send(Application.get_env(:agent_board, :updater_test_pid), :restart_called)
  end

  setup do
    previous = Application.get_env(:agent_board, :updater)
    previous_delay = Application.get_env(:agent_board, :update_restart_delay_ms)
    previous_result = Application.get_env(:agent_board, :updater_result)

    Application.put_env(:agent_board, :updater, UpdaterStub)
    Application.put_env(:agent_board, :update_restart_delay_ms, 60_000)
    Application.put_env(:agent_board, :updater_test_pid, self())

    on_exit(fn ->
      restore(:updater, previous)
      restore(:update_restart_delay_ms, previous_delay)
      restore(:updater_result, previous_result)
      Application.delete_env(:agent_board, :updater_test_pid)
    end)

    :ok
  end

  test "a changed HEAD says it is restarting and schedules the restart", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123", true})
    {:ok, _} = Board.add_repository("fixture", "update")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update")

    html = render_hook(view, "update", %{})

    assert html =~ "Atualizado para abc123"
    assert html =~ "reiniciando o servidor"
    refute html =~ "Já está em dia"
  end

  test "an unchanged HEAD does not pretend to restart", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123", false})
    {:ok, _} = Board.add_repository("fixture", "update-current")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-current")

    html = render_hook(view, "update", %{})

    assert html =~ "Já está em dia (abc123)"
    refute html =~ "reiniciando o servidor"
  end

  test "the explicit restart button schedules the same path", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "restart")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/restart")

    html = render_hook(view, "restart", %{})

    assert html =~ "Reiniciando o servidor"
  end

  defp restore(key, nil), do: Application.delete_env(:agent_board, key)
  defp restore(key, value), do: Application.put_env(:agent_board, key, value)
end
