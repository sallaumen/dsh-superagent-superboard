defmodule AgentBoardWeb.LogsPanelTest do
  @moduledoc """
  Settings → Logs: only warnings/errors, read only while open, pause/resume,
  clear, and honest missing/unreadable states.
  """
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Logs, Superagents}

  setup do
    dir =
      Path.join(System.tmp_dir!(), "agent-board-logs-ui-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    board_log = Path.join(dir, "AgentBoard.log")
    File.write!(board_log, "")

    previous = %{
      log_path: Application.get_env(:agent_board, :log_path),
      superagent_log_dir: Application.get_env(:agent_board, :superagent_log_dir),
      logs_tick_interval: Application.get_env(:agent_board, :logs_tick_interval)
    }

    Application.put_env(:agent_board, :log_path, board_log)
    Application.put_env(:agent_board, :superagent_log_dir, dir)
    Application.put_env(:agent_board, :logs_tick_interval, 25)

    on_exit(fn ->
      restore(:log_path, previous.log_path)
      restore(:superagent_log_dir, previous.superagent_log_dir)
      restore(:logs_tick_interval, previous.logs_tick_interval)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir, board_log: board_log}
  end

  defp restore(key, nil), do: Application.delete_env(:agent_board, key)
  defp restore(key, value), do: Application.put_env(:agent_board, key, value)

  defp repo!(name \\ "logs") do
    {:ok, repo} = Board.add_repository("fixture", name)
    repo
  end

  defp superagent!(repo, profile) do
    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: profile,
        port: 3190 + rem(repo.id, 1000),
        state_dir: Path.join(System.tmp_dir!(), "superagent-#{profile}")
      })

    superagent
  end

  defp board_line(level, message), do: "2026-11-08 21:00:00.000 [#{level}] #{message}"

  defp write_log(path, lines), do: File.write!(path, Enum.join(lines, "\n") <> "\n", [:append])

  defp attach_logs_telemetry do
    handler = "logs-panel-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:agent_board, :logs, :read],
      fn _event, _measurements, _metadata, _config -> send(test_pid, :logs_read) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp flush_logs_read do
    receive do
      :logs_read -> flush_logs_read()
    after
      0 -> :ok
    end
  end

  test "the legacy link opens Settings → Logs with warning and error lines, including the stack trace",
       %{
         conn: conn,
         board_log: board_log
       } do
    repo!()
    write_log(board_log, [board_line("info", "info silenciosa")])
    write_log(board_log, [board_line("warning", "aviso no painel"), "detalhe do aviso"])
    write_log(board_log, [board_line("error", "erro no painel"), "** (RuntimeError) boom"])

    {:ok, view, html} = live(conn, ~p"/?repo=fixture/logs&panel=logs")

    assert has_element?(view, "#panel-settings .settings-nav__item.is-current", "Logs")
    assert html =~ "aviso no painel"
    assert html =~ "detalhe do aviso"
    assert html =~ "erro no painel"
    assert html =~ "** (RuntimeError) boom"
    refute html =~ "info silenciosa"
    assert html =~ "1 aviso"
    assert html =~ "1 erro"
    assert has_element?(view, "#settings-logs[data-logs-timer=on]")
    assert has_element?(view, "#logs-list .ab-logs__entry[data-level=warning]")
  end

  test "a closed panel neither reads nor polls; reopening reads the new lines", %{
    conn: conn,
    board_log: board_log
  } do
    repo!()
    attach_logs_telemetry()
    write_log(board_log, [board_line("warning", "antes de abrir")])

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/logs")

    refute_receive :logs_read, 60
    refute has_element?(view, "#settings-logs")

    view |> element("#board-settings") |> render_click()
    view |> element(".settings-nav [phx-value-section=logs]") |> render_click()
    assert_receive :logs_read, 200
    assert render(view) =~ "antes de abrir"
    assert has_element?(view, "#settings-logs[data-logs-timer=on]")

    view |> element("#panel-settings .panel-close") |> render_click()
    refute has_element?(view, "#settings-logs")
    flush_logs_read()

    write_log(board_log, [board_line("error", "depois de fechar")])
    Process.sleep(120)
    _ = render(view)
    refute_received :logs_read
    refute render(view) =~ "depois de fechar"

    view |> element("#board-settings") |> render_click()
    view |> element(".settings-nav [phx-value-section=logs]") |> render_click()
    assert_receive :logs_read, 200
    assert render(view) =~ "depois de fechar"
    view |> element("#panel-settings .panel-close") |> render_click()
  end

  test "pause stops the timer and resume reads again", %{conn: conn, board_log: board_log} do
    repo!()
    write_log(board_log, [board_line("warning", "visível")])

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/logs&panel=logs")
    assert render(view) =~ "visível"

    view |> element("#settings-logs button[phx-click='logs_pause']") |> render_click()
    assert has_element?(view, "#settings-logs[data-logs-paused=true][data-logs-timer=off]")
    assert render(view) =~ "Retomar"

    write_log(board_log, [board_line("error", "enquanto pausado")])
    Process.sleep(100)
    refute render(view) =~ "enquanto pausado"

    view |> element("#settings-logs button[phx-click='logs_resume']") |> render_click()
    assert has_element?(view, "#settings-logs[data-logs-paused=false][data-logs-timer=on]")
    assert render(view) =~ "enquanto pausado"
  end

  test "clear empties the visible buffer without moving the read offset", %{
    conn: conn,
    board_log: board_log
  } do
    repo!()
    write_log(board_log, [board_line("warning", "antigo")])

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/logs&panel=logs")
    assert render(view) =~ "antigo"

    view |> element("#settings-logs button[phx-click='logs_clear']") |> render_click()
    refute render(view) =~ "antigo"
    assert render(view) =~ "Nenhum aviso ou erro no trecho recente."

    write_log(board_log, [board_line("error", "novo depois de limpar")])
    Process.sleep(100)
    assert render(view) =~ "novo depois de limpar"
    refute render(view) =~ "antigo"
  end

  test "missing and unreadable sources show their state instead of lines", %{
    conn: conn,
    dir: dir
  } do
    repo!()
    other = repo!("other")
    superagent!(other, "superagent-missing")
    File.mkdir_p!(Path.join(dir, "dsh-superagent-missing-keepalive.log"))
    Application.put_env(:agent_board, :log_path, Path.join(dir, "absent.log"))

    {:ok, _view, html} = live(conn, ~p"/?repo=fixture/logs&panel=logs")

    assert html =~ "arquivo ainda não existe"
    assert html =~ "não foi possível ler"
    assert html =~ "Nenhum aviso ou erro no trecho recente."
    assert html =~ "Uma fonte não pôde ser lida"
  end

  test "a registered superagent contributes its keepalive warnings", %{
    conn: conn,
    dir: dir
  } do
    repo!()
    agent_repo = repo!("agent")
    superagent!(agent_repo, "superagent-live")

    write_log(Path.join(dir, "dsh-superagent-live-keepalive.log"), [
      "2026-11-08T16:11:50-0300 status 2: the agent runs but needs a person; not restarting",
      "  {\"errors\": {}, \"health\": {\"github\": \"starting\"}}",
      "2026-11-08T16:12:49-0300 start exited 0"
    ])

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/logs&panel=logs")
    html = render(view)

    assert html =~ "Superagente fixture/agent"
    assert html =~ "needs a person"
    assert html =~ "github"
    assert html =~ "starting"
    assert html =~ "stdout do processo não é lido"
    refute html =~ "start exited 0"
  end

  test "the board log path is the configured one, never a browser value", %{
    conn: conn,
    board_log: board_log
  } do
    repo!()

    {:ok, _view, html} =
      live(conn, ~p"/?repo=fixture/logs&panel=logs&log_path=/etc/passwd")

    assert html =~ board_log
    refute html =~ "/etc/passwd"
  end

  test "filters survive a reload and manual refresh leaves paused reading paused", %{
    conn: conn,
    board_log: board_log
  } do
    repo!()
    write_log(board_log, [board_line("warning", "a warning"), board_line("error", "an error")])
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/logs&panel=settings&section=logs")

    refute has_element?(
             view,
             "#open-logs, #open-superagents, #mobile-panel-superagents, #mobile-panel-logs"
           )

    assert has_element?(view, "#settings-logs", "até #{Logs.cap()} registros")
    view |> element("#logs-filters") |> render_change(%{"source" => "board", "level" => "error"})
    path = "/?level=error&panel=settings&repo=fixture%2Flogs&section=logs&source=board"
    assert_patch(view, path)
    {:ok, reloaded, _} = live(conn, path)
    assert has_element?(reloaded, "#logs-list", "an error")
    refute has_element?(reloaded, "#logs-list", "a warning")
    view |> element("#settings-logs [phx-click=logs_pause]") |> render_click()
    write_log(board_log, [board_line("error", "manual read")])
    view |> element("#settings-logs [phx-click=logs_refresh]") |> render_click()

    assert has_element?(
             view,
             "#settings-logs[data-logs-paused=true][data-logs-timer=off]",
             "manual read"
           )
  end

  test "leaving Logs for another settings section stops every read", %{conn: conn} do
    attach_logs_telemetry()
    {:ok, view, _} = live(conn, ~p"/?panel=logs")
    assert_receive :logs_read
    view |> element(".settings-nav__item[phx-value-section=system]") |> render_click()
    assert_patch(view, "/?panel=settings&section=system")
    refute has_element?(view, "#settings-logs")
    flush_logs_read()
    refute_receive :logs_read, 100
  end

  test "a log written in Latin-1 opens the sheet instead of crashing the socket", %{
    conn: conn,
    board_log: board_log
  } do
    repo!()

    File.write!(
      board_log,
      <<"2026-11-09 09:58:47.886 [error] a voz n", 0xE3, "o foi gerada (HTTP 400)\n">>,
      [:append]
    )

    {:ok, view, html} = live(conn, ~p"/?repo=fixture/logs&panel=logs")

    assert html =~ "a voz não foi gerada"
    assert render(view) =~ "a voz não foi gerada"
    assert Process.alive?(view.pid)
  end

  test "a superagent change while the sheet is open keeps it open and adds the source", %{
    conn: conn,
    dir: dir
  } do
    repo = repo!()
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/logs&panel=logs")

    superagent!(repo, "superagent-tick")

    File.write!(
      Path.join(dir, "dsh-superagent-tick-keepalive.log"),
      "2026-11-09T09:00:00-0300 no manager at 3190\n"
    )

    send(view.pid, :superagents_changed)

    assert render(view) =~ "no manager at 3190"
    assert Process.alive?(view.pid)
  end
end
