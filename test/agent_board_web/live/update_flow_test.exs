defmodule AgentBoardWeb.UpdateFlowTest do
  @moduledoc "The update runs as a staged pipeline and only stops after every stage passed."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  defmodule UpdaterStub do
    def pull, do: result(:updater_result)

    def prepare do
      notify(:prepare_called)
      result(:updater_prepare_result)
    end

    def prepare_build do
      notify(:build_called)
      result(:updater_build_result)
    end

    def prepare_assets do
      notify(:assets_called)
      result(:updater_assets_result)
    end

    def migrate do
      notify(:migrate_called)
      result(:updater_migrate_result)
    end

    def mark_ready do
      notify(:mark_called)
      result(:updater_mark_result)
    end

    def restart, do: notify(:restart_called)

    defp notify(message), do: send(Application.get_env(:agent_board, :updater_test_pid), message)
    defp result(key), do: Application.get_env(:agent_board, key, :ok)
  end

  setup do
    previous =
      for key <- [
            :updater,
            :update_restart_delay_ms,
            :updater_result,
            :updater_prepare_result,
            :updater_build_result,
            :updater_assets_result,
            :updater_migrate_result,
            :updater_mark_result,
            :board_stopper
          ],
          into: %{},
          do: {key, Application.get_env(:agent_board, key)}

    test_pid = self()

    Application.put_env(:agent_board, :updater, UpdaterStub)
    Application.put_env(:agent_board, :update_restart_delay_ms, 60_000)
    Application.put_env(:agent_board, :updater_test_pid, self())
    Application.put_env(:agent_board, :board_stopper, fn -> send(test_pid, :stopped) end)

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:agent_board, key),
          else: Application.put_env(:agent_board, key, value)
      end

      Application.delete_env(:agent_board, :updater_test_pid)
    end)

    :ok
  end

  test "a successful update runs every stage and restarts only at the end", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    {:ok, _} = Board.add_repository("fixture", "update")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update")

    html = render_hook(view, "update", %{})
    html = render_async(view) || html

    assert html =~ "Atualizado para abc123"
    assert html =~ "reiniciando o servidor"
    assert html =~ "Buscando a main"
    assert html =~ "Preparando dependências"
    assert html =~ "Compilando o build novo"
    assert html =~ "Gerando os assets"
    assert html =~ "Aplicando migrações"
    assert html =~ "Build pronto"

    for message <- [
          :prepare_called,
          :build_called,
          :assets_called,
          :migrate_called,
          :mark_called,
          :restart_called,
          :stopped
        ] do
      assert_received ^message
    end
  end

  test "a dependency failure keeps the old board up", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    Application.put_env(:agent_board, :updater_prepare_result, {:error, {:mix, 1, "hex down"}})
    {:ok, _} = Board.add_repository("fixture", "update-prepare-failed")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-prepare-failed")

    html = render_hook(view, "update", %{})
    html = render_async(view) || html

    assert html =~ "A atualização parou no meio"
    assert html =~ "o board continua no código antigo"
    refute html =~ "reiniciando o servidor"
    refute_received :restart_called
    refute_received :stopped
  end

  test "a compile failure keeps the old board up", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    Application.put_env(:agent_board, :updater_build_result, {:error, {:mix, 1, "boom"}})
    {:ok, _} = Board.add_repository("fixture", "update-compile-failed")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-compile-failed")

    html = render_hook(view, "update", %{})
    html = render_async(view) || html

    assert html =~ "A atualização parou no meio"
    refute_received :restart_called
    refute_received :stopped
  end

  test "a failed pull does not pretend to restart", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:error, :no_network})
    {:ok, _} = Board.add_repository("fixture", "update-failed")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-failed")

    html = render_hook(view, "update", %{})
    html = render_async(view) || html

    assert html =~ "A atualização parou no meio"
    refute html =~ "reiniciando o servidor"
    refute_received :restart_called
  end

  test "the explicit restart button schedules the same path", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "restart")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/restart")

    html = render_hook(view, "restart", %{})

    assert html =~ "Reiniciando o servidor"
    assert html =~ "Reiniciando o board"
  end
end
