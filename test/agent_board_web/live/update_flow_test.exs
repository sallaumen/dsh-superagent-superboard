defmodule AgentBoardWeb.UpdateFlowTest do
  @moduledoc "The update button schedules a real restart and never lies about being current."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  defmodule UpdaterStub do
    def pull, do: Application.get_env(:agent_board, :updater_result)
    def restart, do: send(Application.get_env(:agent_board, :updater_test_pid), :restart_called)
  end

  setup do
    previous = Application.get_env(:agent_board, :updater)
    previous_delay = Application.get_env(:agent_board, :update_restart_delay_ms)
    previous_result = Application.get_env(:agent_board, :updater_result)
    previous_stopper = Application.get_env(:agent_board, :board_stopper)
    test_pid = self()

    Application.put_env(:agent_board, :updater, UpdaterStub)
    Application.put_env(:agent_board, :update_restart_delay_ms, 60_000)
    Application.put_env(:agent_board, :updater_test_pid, self())
    Application.put_env(:agent_board, :board_stopper, fn -> send(test_pid, :stopped) end)

    on_exit(fn ->
      restore(:updater, previous)
      restore(:update_restart_delay_ms, previous_delay)
      restore(:updater_result, previous_result)
      restore(:board_stopper, previous_stopper)
      Application.delete_env(:agent_board, :updater_test_pid)
    end)

    :ok
  end

  test "a successful update restarts immediately, without losing the stop", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    {:ok, _} = Board.add_repository("fixture", "update")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update")

    html = render_hook(view, "update", %{})

    assert html =~ "Atualizado para abc123"
    assert html =~ "reiniciando o servidor"
    assert_received :restart_called
    assert_received :stopped
    refute html =~ "Já está em dia"
  end

  test "a failed update does not pretend to restart", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:error, :no_network})
    {:ok, _} = Board.add_repository("fixture", "update-failed")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-failed")

    html = render_hook(view, "update", %{})

    assert html =~ "A atualização falhou"
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
