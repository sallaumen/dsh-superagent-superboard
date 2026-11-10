defmodule AgentBoardWeb.UpdateFlowTest do
  @moduledoc "The update runs as a staged pipeline and only stops after every stage passed."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Actions, Board}
  alias AgentBoard.System.UpdateRun

  defmodule UpdaterStub do
    def pull, do: result(:updater_result)

    def prepare do
      notify(:prepare_called)

      case Application.get_env(:agent_board, :updater_prepare_wait) do
        nil ->
          :ok

        pid ->
          send(pid, {:prepare_waiting, self()})

          receive do
            :continue -> :ok
          after
            5_000 -> :ok
          end
      end

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

    def freeze_config_files, do: []

    def restore_config_files(_times) do
      notify(:restore_called)
      :ok
    end

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
            :updater_prepare_wait,
            :board_stopper
          ],
          into: %{},
          do: {key, Application.get_env(:agent_board, key)}

    test_pid = self()

    UpdateRun.subscribe()
    UpdateRun.release_reload()
    on_exit(&UpdateRun.release_reload/0)

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

  test "a second start while one runs joins it and runs no second pipeline" do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    Application.put_env(:agent_board, :updater_prepare_wait, self())

    {:ok, _first} = UpdateRun.start(Actions.owner(:ui))
    assert_receive {:prepare_waiting, first}, 5_000
    {:ok, _second} = UpdateRun.start(Actions.owner(:ui))

    refute_receive {:prepare_waiting, _second}, 500
    assert UpdateRun.running?()

    send(first, :continue)
    assert_receive {:update_finished, {:ok, "abc123"}}, 5_000
    finished()
  end

  test "a successful update runs every stage and restarts only at the end", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    {:ok, _} = Board.add_repository("fixture", "update")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update")

    html = run_update(view)

    assert html =~ "Atualizado para abc123"
    assert html =~ "reiniciando o servidor"
    assert html =~ "Buscando a main"
    assert html =~ "Preparando dependências"
    assert html =~ "Compilando o build novo"
    assert html =~ "Gerando os assets"
    assert html =~ "Aplicando migrações"
    assert html =~ "Build pronto"

    assert_receive :restore_called
    assert_receive :restore_called

    for message <- [
          :prepare_called,
          :build_called,
          :assets_called,
          :migrate_called,
          :mark_called,
          :restart_called,
          :stopped
        ] do
      assert_receive ^message
    end

    finished()
  end

  test "a dependency failure keeps the old board up", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    Application.put_env(:agent_board, :updater_prepare_result, {:error, {:mix, 1, "hex down"}})
    {:ok, _} = Board.add_repository("fixture", "update-prepare-failed")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-prepare-failed")

    html = run_update(view)

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

    html = run_update(view)

    assert html =~ "A atualização parou no meio"
    refute_received :restart_called
    refute_received :stopped
  end

  test "a failed pull does not pretend to restart", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:error, :no_network})
    {:ok, _} = Board.add_repository("fixture", "update-failed")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-failed")

    html = run_update(view)

    assert html =~ "A atualização parou no meio"
    refute html =~ "reiniciando o servidor"
    refute_received :restart_called
  end

  test "the update finishes after the page that asked for it is gone", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    Application.put_env(:agent_board, :updater_prepare_wait, self())
    {:ok, _} = Board.add_repository("fixture", "update-page-gone")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-page-gone")

    render_hook(view, "update", %{})
    assert_receive {:prepare_waiting, flow}

    # The fast-forward's live reload does this to the page.
    Process.flag(:trap_exit, true)
    ref = Process.monitor(view.pid)
    Process.exit(view.pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}

    send(flow, :continue)

    for message <- [:build_called, :mark_called, :restart_called, :stopped] do
      assert_receive ^message
    end

    finished()
  end

  test "a page opened during the update joins it", %{conn: conn} do
    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    Application.put_env(:agent_board, :updater_prepare_wait, self())
    {:ok, _} = Board.add_repository("fixture", "update-join")
    {:ok, first, _html} = live(conn, ~p"/?repo=fixture/update-join")

    render_hook(first, "update", %{})
    assert_receive {:prepare_waiting, flow}

    {:ok, second, _html} = live(conn, ~p"/?repo=fixture/update-join")
    assert render(second) =~ "Buscando a main"
    assert UpdateRun.reload_held?()

    send(flow, :continue)
    assert_receive :stopped
    assert eventually(second, "Atualizado para abc123")
    finished()
  end

  test "a failure after the pull keeps the reload held; a failed pull does not", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "update-held")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/update-held")

    Application.put_env(:agent_board, :updater_result, {:error, :no_network})
    run_update(view)
    refute UpdateRun.reload_held?()

    Application.put_env(:agent_board, :updater_result, {:ok, "abc123"})
    Application.put_env(:agent_board, :updater_build_result, {:error, {:mix, 1, "boom"}})
    run_update(view)
    assert UpdateRun.reload_held?()
  end

  test "while the reload is held the dev checks leave the request alone" do
    conn = Phoenix.ConnTest.build_conn()

    :persistent_term.put({UpdateRun, :reload_held}, true)
    assert AgentBoardWeb.DevReload.call(conn, AgentBoardWeb.DevReload.init([])) == conn
  end

  # A socket connect ran Phoenix.CodeReloader outside DevReload: any page open
  # during an update recompiled the new sources into the serving node, which
  # then answered 500 and queried columns the migration had not created yet.
  test "no socket recompiles on connect, so the hold covers every reload" do
    for {_path, _socket, opts} <- AgentBoardWeb.Endpoint.__sockets__(),
        transport <- [:websocket, :longpoll],
        is_list(opts[transport]) do
      assert opts[transport][:code_reloader] == false
    end

    # The live-reload socket exists only in dev, and it was the trigger: it
    # connects on every page load.
    assert File.read!("lib/agent_board_web/endpoint.ex") =~
             "Phoenix.LiveReloader.Socket,\n      websocket: [code_reloader: false]"
  end

  test "the explicit restart button schedules the same path", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "restart")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/restart")

    html = render_hook(view, "restart", %{})

    assert html =~ "Reiniciando o servidor"
    assert html =~ "Reiniciando o board"
  end

  defp run_update(view) do
    render_hook(view, "update", %{})
    assert_receive {:update_finished, result}
    finished()

    case result do
      {:ok, sha} -> eventually(view, "Atualizado para #{sha}")
      {:error, _reason} -> eventually(view, "A atualização parou no meio")
    end

    render(view)
  end

  defp finished do
    if UpdateRun.running?() do
      Process.sleep(10)
      finished()
    end
  end

  # The test and the page get the same broadcast; the page may be a step behind.
  defp eventually(view, text, tries \\ 40)
  defp eventually(view, text, 0), do: flunk("never rendered #{text}: #{render(view)}")

  defp eventually(view, text, tries) do
    if render(view) =~ text do
      true
    else
      Process.sleep(25)
      eventually(view, text, tries - 1)
    end
  end
end
