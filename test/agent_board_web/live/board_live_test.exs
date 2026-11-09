defmodule AgentBoardWeb.BoardLiveTest do
  @moduledoc "The board's UI: the columns render and the tasks can be created."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox

  # The LiveView runs in its own process: allow it to use the test's
  # transaction, which is the supported way to keep async: true.
  defp allow_view(view) do
    Sandbox.allow(AgentBoard.Repo, self(), view.pid)
    view
  end

  alias AgentBoard.AI.Call
  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}

  test "the page CSP lets the voice play blob media", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert get_resp_header(conn, "content-security-policy") |> List.first() =~
             "media-src 'self' blob:"
  end

  test "issues_unavailable is amber, not red", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Board.log_event(repo.id, "issues_unavailable", "sallaumen/arena-rogue", %{"reason" => "404"})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "text-warning"
    refute html =~ "text-error"
  end

  test "a per-item error event is shown as an error", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Board.log_event(repo.id, "issue_error", "#7", %{"reason" => "boom"})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "text-error"
  end

  test "the sync detail says 1 erro, not 1 erros", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"errors" => 1, "issues" => 0})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "1 erro"
    refute html =~ "1 erros"
    assert html =~ "Com erros"
  end

  test "a long error payload is truncated in the activity", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Board.log_event(repo.id, "sync_error", "x", %{"reason" => String.duplicate("boom ", 80)})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "…"
    refute html =~ String.duplicate("boom ", 80)
  end

  test "the beacon finds the sync beyond the 20 recent events", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "health")
    Board.log_event(repo.id, "sync", "fixture/health", %{"errors" => 0})
    for n <- 1..21, do: Board.log_event(repo.id, "comment_error", "##{n}", %{})

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/health")
    assert has_element?(view, ".ab-beacon[data-state=live]", "Ao vivo")
    assert has_element?(view, ".ab-sync-pop", "GitHub (PRs, CI)")
    refute has_element?(view, ".ab-beacon[data-state=offline]")
  end

  test "the beacon describes the last outcome without pretending a failure refreshed data", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "freshness")
    Board.log_event(repo.id, "sync", "fixture/freshness", %{"errors" => 0})
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/freshness")
    assert has_element?(view, ".ab-beacon[data-state=live]", "Ao vivo")

    Board.log_event(repo.id, "sync_error", "fixture/freshness", %{"reason" => "offline"})
    send(view.pid, :board_updated)
    assert has_element?(view, ".ab-beacon[data-state=offline]", "Sem conexão")
    assert has_element?(view, ".ab-frozen", "Mostrando o que sabíamos")
    assert has_element?(view, ".ab-sync-pop", "Falhou")
  end

  test "a failed sync supersedes the last clean outcome", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "health")
    Board.log_event(repo.id, "sync", "fixture/health", %{"errors" => 0})
    Board.log_event(repo.id, "sync_error", "fixture/health", %{"reason" => "offline"})

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/health")
    assert has_element?(view, ".ab-beacon[data-state=offline]", "Sem conexão")
    assert has_element?(view, ".ab-sync-pop", "Falhou")
    assert has_element?(view, ".ab-frozen", "Mostrando o que sabíamos")
    refute has_element?(view, ".ab-beacon[data-state=live]")
  end

  test "the stale banner and the beacon speak the owner's clock, not UTC", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "clock")
    Board.log_event(repo.id, "sync", "fixture/clock", %{"errors" => 0})
    Board.log_event(repo.id, "sync_error", "fixture/clock", %{"reason" => "offline"})
    at = Board.sync_snapshot(repo).last_success.inserted_at
    expected = AgentBoard.Time.local_time(at, 180)

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"board_tz_offset" => 180})
      |> live(~p"/?repo=fixture/clock")

    assert has_element?(view, ".ab-frozen", "Mostrando o que sabíamos às #{expected}")
    assert has_element?(view, ".ab-beacon[data-state=offline]", "dados de #{expected}")
  end

  test "a transcript outside the composer is a conversation turn, never a draft", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    render_hook(view, "voice_transcript", %{"text" => "  show blocked tasks  "})

    refute render(view) =~ ~s(data-panel="voice")
    refute has_element?(view, "#voice-command-text")
    assert [%{role: "owner", text: "show blocked tasks"} | _] = AgentBoard.Conversation.recent()
    assert AgentBoard.Repo.aggregate(Task, :count) == 0
  end

  test "Speak status pushes the board summary", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue&panel=settings")
    view |> element(".settings-nav__item[phx-value-section=voice]") |> render_click()

    view |> element("button", "Falar status") |> render_click()

    assert_push_event(view, "speak", %{text: text})
    assert is_binary(text)
    assert text != ""
  end

  test "a failed ask shows an error, not Question sent", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 801,
      title: "Ask fail",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    view |> element("[data-task]") |> render_click()

    view
    |> element("#ask-agent")
    |> render_submit(%{"body" => "hi"})

    render_async(view, 2_000)

    assert render(view) =~ "não chegou ao GitHub"
    # The text comes back to the box, so nothing typed is lost.
    assert has_element?(view, "#ask-body", "hi")
  end

  test "the conversation opens in the inspector on small screens", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 303,
      title: "Conv mobile",
      state: "queued"
    })
    |> Repo.insert!()

    task = Repo.get_by(Task, number: 303)

    Board.upsert_comment(
      task,
      %{"id" => 1, "user" => %{"login" => "sallaumen"}, "body" => "hi"},
      "sallaumen-agent"
    )

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("[data-task]") |> render_click()

    assert has_element?(view, "#conversation.ab-insp")
    assert has_element?(view, "#conversation .ab-msg", "hi")
  end

  test "merged history exposes every loaded pull in one scroll region", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "history")
    now = DateTime.utc_now()

    for number <- 1..7 do
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: number,
        title: "Merged pull #{number}",
        state: "merged",
        merged_at: DateTime.add(now, number, :second)
      })
      |> Repo.insert!()
    end

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/history")

    assert has_element?(view, "#merged-column-history .archive-count", "7 carregados")

    assert has_element?(
             view,
             "#merged-column-history .archive-count[aria-label='7 pull requests loaded']"
           )

    assert has_element?(view, "#merge-trend", "7 nos últimos 7 dias UTC · histórico carregado")
    assert has_element?(view, "#merged-column-history[tabindex='-1']")
    assert has_element?(view, "#merged-list[aria-label='Lista de PRs mesclados']")
    assert has_element?(view, "#merged-list article:nth-child(5)", "Merged pull 3")
    assert has_element?(view, "#merged-list article:nth-child(6)", "Merged pull 2")
    assert has_element?(view, "#merged-list article:nth-child(7)", "Merged pull 1")
    refute has_element?(view, "#merged-column-history summary")
    refute has_element?(view, "#merged-column-history button[phx-click=act]")
  end

  test "the merge log links to the full history only when there is one", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "empty-work")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/empty-work")
    refute has_element?(view, "#sec-log button", "Histórico")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 7,
      title: "Merged pull",
      state: "merged",
      merged_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    send(view.pid, :board_updated)
    assert has_element?(view, "#sec-log button", "Histórico")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 8,
      title: "Queued work",
      state: "queued"
    })
    |> Repo.insert!()

    send(view.pid, :board_updated)
    assert has_element?(view, "#sec-log button", "Histórico")
  end

  test "scrolling the merged list loads fifty more without duplicates or losing pages", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "scroll-history")
    now = DateTime.utc_now()

    for number <- 1..120 do
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: number,
        title: "Merged pull #{number}",
        state: "merged",
        merged_at: DateTime.add(now, number)
      })
      |> Repo.insert!()
    end

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/scroll-history")
    assert has_element?(view, "#merged-list[phx-viewport-bottom=load_more_merged]")
    assert has_element?(view, "#merged-column-history .archive-count", "50 carregados")

    first_tail = view |> element("#merged-list .archive-tail") |> render() |> tail_id()
    render_hook(view, "load_more_merged", %{"id" => first_tail})
    assert has_element?(view, "#merged-column-history .archive-count", "100 carregados")

    render_hook(view, "load_more_merged", %{"id" => first_tail})
    assert has_element?(view, "#merged-column-history .archive-count", "100 carregados")

    second_tail = view |> element("#merged-list .archive-tail") |> render() |> tail_id()
    render_hook(view, "load_more_merged", %{"id" => second_tail})
    assert has_element?(view, "#merged-column-history .archive-count", "120 carregados")
    refute has_element?(view, "#merged-list[phx-viewport-bottom]")
    refute has_element?(view, "#merged-list .archive-tail[id]")

    send(view.pid, :board_updated)
    assert has_element?(view, "#merged-column-history .archive-count", "120 carregados")
    assert length(Regex.scan(~r/id="pull-\d+"/, render(view))) == 120

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 121,
      title: "Newest merge",
      state: "merged",
      merged_at: DateTime.add(now, 121)
    })
    |> Repo.insert!()

    send(view.pid, :board_updated)
    assert has_element?(view, "#merged-column-history .archive-count", "120 carregados")
    assert has_element?(view, "#merged-list", "Newest merge")
    assert length(Regex.scan(~r/id="pull-\d+"/, render(view))) == 120

    newest_tail = view |> element("#merged-list .archive-tail") |> render() |> tail_id()
    render_hook(view, "load_more_merged", %{"id" => newest_tail})
    assert has_element?(view, "#merged-column-history .archive-count", "121 carregados")
    assert length(Regex.scan(~r/id="pull-\d+"/, render(view))) == 121

    resume = %{"repo" => "fixture/scroll-history", "merged" => 121, "tasks" => %{}}

    {:ok, reconnected, _html} =
      conn
      |> put_connect_params(%{"board_resume" => resume})
      |> live(~p"/?repo=fixture/scroll-history")

    assert has_element?(
             reconnected,
             "#merged-column-history .archive-count",
             "121 carregados"
           )

    assert length(Regex.scan(~r/id="pull-\d+"/, render(reconnected))) == 121
  end

  defp tail_id(html) do
    [_, id] = Regex.run(~r/id="(merged-tail-\d+)"/, html)
    id
  end

  test "the queue shows 8, expands in pages and keeps its total through a broadcast", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "task-pages")

    for number <- 1..120 do
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: number,
        title: "Queued task #{number}",
        state: "queued"
      })
      |> Repo.insert!()
    end

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/task-pages")
    assert has_element?(view, "#sec-queue .ab-sec__count", "120")
    assert queue_rows(view) == 8
    assert has_element?(view, "button", "Mais 112 na fila")

    view |> element("button", "Mais 112 na fila") |> render_click()
    assert queue_rows(view) == 50
    assert has_element?(view, "#sec-queue .ab-sec__count", "120")
    assert has_element?(view, "button", "Mais 70 na fila")

    view |> element("button", "Mais 70 na fila") |> render_click()
    assert queue_rows(view) == 100
    view |> element("button", "Mais 20 na fila") |> render_click()
    assert queue_rows(view) == 120
    refute has_element?(view, "button", "Mais")

    send(view.pid, :board_updated)
    assert has_element?(view, "#sec-queue .ab-sec__count", "120")
    assert queue_rows(view) == 120

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 121,
      title: "Arrived after broadcast",
      state: "queued"
    })
    |> Repo.insert!()

    send(view.pid, :board_updated)
    assert has_element?(view, "#sec-queue .ab-sec__count", "121")
    assert has_element?(view, "#sec-queue", "Arrived after broadcast")
    assert queue_rows(view) == 121
    refute has_element?(view, "button", "Mais 1 na fila")
  end

  defp queue_rows(view), do: render(view) |> then(&length(Regex.scan(~r/class="ab-row"/, &1)))

  test "the merge chart counts only dated records within the visible UTC window", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "trend")
    today = DateTime.new!(Date.utc_today(), ~T[12:00:00], "Etc/UTC")

    for {number, days_ago} <- [{1, 0}, {2, 1}, {3, 8}] do
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: number,
        title: "Merge #{number}",
        state: "merged",
        merged_at: DateTime.add(today, -days_ago, :day)
      })
      |> Repo.insert!()
    end

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/trend")

    assert has_element?(view, "#merge-trend", "2 nos últimos 7 dias UTC · histórico carregado")

    assert has_element?(
             view,
             "#merge-trend li[aria-label='#{Date.utc_today()}: 1 mesclagens carregadas']"
           )

    old_date = Date.add(Date.utc_today(), -8)
    refute has_element?(view, "#merge-trend li[aria-label^='#{old_date}']")
  end

  test "empty merged history has no expansion control", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "empty-history")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/empty-history")

    assert has_element?(view, "#merged-column-history", "Nenhum PR mesclado ainda.")
    refute has_element?(view, "#merge-trend")
    assert has_element?(view, "#merged-list", "Nenhum PR mesclado ainda.")
    refute has_element?(view, "#merged-column-history summary")
  end

  test "missing AI measurements remain unknown", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "measurements")

    %Call{}
    |> Call.changeset(%{
      name: "refine_request",
      engine: "deepseek",
      status: "error",
      duration_ms: nil,
      input_tokens: nil,
      output_tokens: nil
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/measurements")

    assert has_element?(view, ".ai-call-metrics div:first-child", "Latênciadesconhecido")
    assert has_element?(view, ".ai-call-metrics div:nth-child(2)", "Usodesconhecido")
    assert has_element?(view, ".ai-call-metrics div:last-child", "Custo est.desconhecido")
    assert has_element?(view, ".ai-call-reason", "Motivo não registrado")
    refute has_element?(view, ".ai-call-metrics", "0ms")
    refute has_element?(view, ".ai-call-metrics", "0 tokens")
  end

  test "the AI panel shows a recorded failure reason", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "ai-failure")

    %Call{}
    |> Call.changeset(%{
      name: "split_request",
      engine: "deepseek",
      status: "error",
      error: "malformed_output"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/ai-failure&panel=ai")
    assert has_element?(view, "#panel-ai .ai-call-reason", "malformed_output")
  end

  test "a merged pull shows its review badge", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 404,
      title: "Badge PR",
      state: "merged",
      merged_at: DateTime.utc_now(),
      review_state: "changes_requested"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Badge PR"
    assert html =~ "changes requested"
  end

  test "a merged pull shows its CI badge", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 405,
      title: "CI PR",
      state: "merged",
      merged_at: DateTime.utc_now(),
      checks_state: "failure"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "CI PR"
    assert html =~ "ci failed"
  end

  test "a failed CI names the check", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 406,
      title: "Named CI",
      state: "merged",
      merged_at: DateTime.utc_now(),
      checks_state: "failure",
      checks_failed: "compile"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "ci failed: compile"
  end

  test "a pull with no reviews says so instead of hiding the badge", %{conn: conn} do
    # arena-rogue has few merged pulls, so one more still fits the 30 window.
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 407,
      title: "No review PR",
      state: "merged",
      merged_at: DateTime.utc_now(),
      review_state: "none",
      checks_state: "none"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/")

    # the board opens on o_colmex; switch to arena-rogue
    view |> element("#repo-select") |> render_change(%{"repo" => "sallaumen/arena-rogue"})

    assert render(view) =~ "no review"
    assert render(view) =~ "no ci"
  end

  test "the board sends a content security policy", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert Enum.any?(conn.resp_headers, fn {k, v} ->
             k == "content-security-policy" and v =~ "default-src"
           end)
  end

  test "the version panel shows the running sha and a check button", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue&panel=settings")
    view |> element(".settings-nav__item[phx-value-section=version]") |> render_click()

    assert has_element?(view, ".settings-nav__item.is-current", "Versão")
    assert has_element?(view, "#version-panel", "rodando")
    assert has_element?(view, "#version-panel button", "Verificar")
  end

  test "work actions live in the top bar while settings holds preferences", %{
    conn: conn
  } do
    {:ok, _repo} = Board.add_repository("fixture", "settings")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/settings")

    assert has_element?(view, "#board-settings", "Configurações")
    view |> element("#board-settings") |> render_click()
    assert_patch(view, "/?panel=settings&repo=fixture%2Fsettings")
    assert has_element?(view, "#settings-dispatch-title", "Despacho local")
    assert has_element?(view, ".settings-nav__item.is-current", "Despacho local")

    assert has_element?(
             view,
             "#settings-current-section section[aria-labelledby=settings-inspect-title][hidden]"
           )

    view |> element(".settings-nav__item[phx-value-section=inspect]") |> render_click()
    assert has_element?(view, ".settings-nav__item.is-current", "Inspecionar")

    refute has_element?(
             view,
             "#settings-current-section section[aria-labelledby=settings-inspect-title][hidden]"
           )

    assert has_element?(view, "#board-tools #open-intake", "Dividir pedido")
    assert has_element?(view, "#board-tools #open-create", "Novo pedido")
    refute has_element?(view, "#board-tools #open-activity")
    assert has_element?(view, "#board-settings-panel #open-activity", "Atividade")
    assert has_element?(view, "#board-settings-panel #open-ai", "Chamadas de IA")

    view |> element("#open-activity") |> render_click()
    assert_patch(view, "/?panel=activity&repo=fixture%2Fsettings")
    assert has_element?(view, "#board-page[data-panel=activity]")
  end

  test "new request opens in the composer and closes to the board", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "create-panel")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/create-panel")

    assert has_element?(view, "#board-tools #open-create", "Novo pedido")
    assert has_element?(view, "#panel-composer #composer-form[phx-submit=composer_submit]")
    assert has_element?(view, "#panel-composer textarea#composer-text")

    view |> element("#open-create") |> render_click()
    assert_patch(view, "/?panel=composer&repo=fixture%2Fcreate-panel")
    assert has_element?(view, "#board-page[data-panel=composer]")

    view |> element("#panel-composer button[aria-label='Fechar (Esc)']") |> render_click()
    assert has_element?(view, "#board-page[data-panel='']")
  end

  test "the AI panel shows the last calls", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    %Call{}
    |> Call.changeset(%{
      name: "refine_request",
      engine: "deepseek",
      model: "deepseek-flash",
      tier: "fast",
      status: "ok",
      input_tokens: 10,
      output_tokens: 20,
      duration_ms: 123,
      cost_micros: 1_120
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "refine_request"
    assert html =~ "deepseek"
    assert html =~ "123ms"
    assert html =~ "30 tokens"
    assert html =~ "Custo est."
    assert html =~ "$0.00112"
  end

  test "the empty repository says there is nothing yet", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert has_element?(view, ".ab-empty", "Sem dados ainda.")
  end

  test "a blocked task lands in Precisa de você and marks the rail", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "blocked")
    Board.log_event(repo.id, "sync", "fixture/blocked", %{"errors" => 0})

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 42,
        title: "Needs a decision",
        state: "blocked"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/blocked")

    assert has_element?(view, "#sec-needs #task-#{task.id}", "Needs a decision")
    assert has_element?(view, "button.ab-repo[aria-current=true] .ab-repo__n--halt", "1")
    refute has_element?(view, "#sec-now #task-#{task.id}")
  end

  test "a question with a workpad quotes its Pergunta, without a question mark", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "workpad")
    Board.log_event(repo.id, "sync", "fixture/workpad", %{"errors" => 0})

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 31,
        title: "Boss fight",
        state: "question"
      })
      |> Repo.insert!()

    Board.upsert_comment(
      task,
      %{
        "id" => 1,
        "user" => %{"login" => "sallaumen-agent"},
        "body" => """
        This is by an automated agent, not a human.

        ## Relatório do agente

        ### Plano
        Trocar a arena. Perguntar? Não: isto é o plano.

        ### Validação

        ### Pergunta
        Devo manter o boss na arena ou tirar

        ### Bloqueio
        """
      },
      "sallaumen-agent"
    )

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/workpad")

    assert has_element?(view, "#sec-needs #task-#{task.id}", "O agente perguntou:")

    assert has_element?(
             view,
             "#sec-needs #task-#{task.id}",
             "Devo manter o boss na arena ou tirar"
           )

    refute has_element?(view, "#sec-needs #task-#{task.id}", "automated agent")
    refute has_element?(view, "#sec-needs #task-#{task.id}", "Perguntar?")
  end

  test "a review names its PR, links it and keeps the CI honest", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "review")
    Board.log_event(repo.id, "sync", "fixture/review", %{"errors" => 0})

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 27,
        title: "Pixel art",
        state: "ready"
      })
      |> Repo.insert!()

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 28,
      title: "Replace geometric arena art",
      state: "open",
      checks_state: "failure",
      checks_failed: "gates",
      url: "https://github.com/fixture/review/pull/28"
    })
    |> Repo.insert!()

    Board.upsert_comment(
      task,
      %{
        "id" => 1,
        "user" => %{"login" => "sallaumen-agent"},
        "body" => "Feito: o [PR #28](https://github.com/fixture/review/pull/28) está pronto."
      },
      "sallaumen-agent"
    )

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/review")

    assert has_element?(view, "#sec-needs #task-#{task.id}", "PR #28 pronto para revisão")
    assert has_element?(view, "#sec-needs #task-#{task.id} .ab-tag", "CI local ?")

    assert has_element?(
             view,
             ~s(#sec-needs #task-#{task.id} a[href="https://github.com/fixture/review/pull/28"]),
             "Abrir PR #28"
           )

    refute render(view) =~ "GitHub Actions passou"
  end

  test "the repo query param selects a repository", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "o_colmex")
    {:ok, arena} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: arena.id,
      kind: "issue",
      number: 601,
      title: "Arena only",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "Arena only"
  end

  test "a board_updated message reloads the board", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    assert html =~ "Sem dados ainda."

    # a task appears behind the view's back
    repo = Board.repository_by_slug("sallaumen/arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 701,
      title: "Arrived by broadcast",
      state: "running"
    })
    |> Repo.insert!()

    send(view.pid, :board_updated)

    assert render(view) =~ "Arrived by broadcast"
  end

  test "broadcasts keep a single stable card and the open conversation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "stable")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 9,
        title: "Stable task",
        state: "queued"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/stable")
    view |> element("#task-#{task.id}") |> render_click()

    task |> Task.changeset(%{state: "running"}) |> Repo.update!()
    for _ <- 1..3, do: send(view.pid, :board_updated)

    html = render(view)
    assert length(Regex.scan(~r/id="task-#{task.id}"/, html)) == 1
    assert has_element?(view, "#sec-now #task-#{task.id}")
    assert has_element?(view, "#conversation-title", "Stable task")
    assert has_element?(view, "#ask-agent textarea[name=body]")
  end

  test "switching repos moves the subscription to the new repository", %{conn: conn} do
    {:ok, colmex} = Board.add_repository("sallaumen", "o_colmex")
    {:ok, arena} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/o_colmex")

    old_topic = "board:#{colmex.id}"
    new_topic = "board:#{arena.id}"

    assert subscribed?(view.pid, old_topic)

    view
    |> element("#repo-select")
    |> render_change(%{"repo" => "sallaumen/arena-rogue"})

    refute subscribed?(view.pid, old_topic)
    assert subscribed?(view.pid, new_topic)
  end

  defp subscribed?(pid, topic) do
    AgentBoard.PubSub
    |> Registry.lookup(topic)
    |> Enum.any?(fn {subscriber, _meta} -> subscriber == pid end)
  end

  test "selecting a repository updates the url", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "o_colmex")
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#repo-select")
    |> render_change(%{"repo" => "sallaumen/arena-rogue"})

    assert_patch(view, "/?repo=sallaumen%2Farena-rogue")
  end

  test "an unknown repository slug renders the empty board", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/?repo=nobody/nothing")

    assert html =~ "Sem dados ainda."
  end

  test "the sync line is announced politely", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(role="status")
    assert html =~ ~s(aria-live="polite")
  end

  test "external links open with noopener", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 501,
      title: "Linked pull",
      state: "merged",
      merged_at: DateTime.utc_now(),
      url: "https://github.com/sallaumen/arena-rogue/pull/501"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ ~s(rel="noopener noreferrer")
  end

  test "the controls carry accessible names", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ ~s(aria-label="Repositório")
    view |> element("#board-settings") |> render_click()
    view |> element(".settings-nav__item[phx-value-section=repositories]") |> render_click()
    assert has_element?(view, "label:has(input[name=owner])", "Dono")
    assert has_element?(view, "label:has(input[name=name])", "Repositório")
  end

  test "the rail carries the brand and the current repository", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert has_element?(view, ".ab-rail .ab-brand", "Agent Board")
    assert has_element?(view, ".ab-top__repo h1", "arena-rogue")
  end

  test "the board renders the work sections", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 1,
      title: "Keep the sections visible",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "Agora"
    assert html =~ "Precisa de você"
    assert html =~ "Fila"
    assert html =~ "Mesclados"
  end

  test "the settings panel keeps named repository tracking fields", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?panel=settings")
    view |> element(".settings-nav__item[phx-value-section=repositories]") |> render_click()

    assert has_element?(view, "#board-settings-panel label", "Dono")
    assert has_element?(view, "#board-settings-panel label", "Repositório")
    assert has_element?(view, "#board-settings-panel #track-repo[phx-submit=add_project]")
  end

  test "the reading columns switch to one column through a container query", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 2,
      title: "Keep the columns visible",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "ab-cols"
    assert html =~ "ab-col"
  end

  test "an idle board marks the columns so the history takes the width", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "idle")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 1,
      title: "Merged pull",
      state: "merged",
      merged_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/idle")
    assert has_element?(view, ".ab-cols[data-idle=true]")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 2,
      title: "Queued work",
      state: "queued"
    })
    |> Repo.insert!()

    send(view.pid, :board_updated)
    assert has_element?(view, ".ab-cols[data-idle=false]")
  end

  test "the board renders the tracked repository", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "sallaumen/arena-rogue"
  end

  test "the board renders without a repository", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Nenhum repositório acompanhado."
  end

  test "a broadcast reaches the board subscribers", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, _view, _html} = live(conn, ~p"/")

    assert Board.subscribe(repo.id) == :ok
    Board.broadcast(repo.id)

    assert_receive :board_updated
  end

  test "the board opens on o_colmex when it is tracked", %{conn: conn} do
    {:ok, _arena} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, _colmex} = Board.add_repository("sallaumen", "o_colmex")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "o_colmex"
  end

  test "an activity row with errors is highlighted", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"pulls" => 1, "errors" => 2})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "errors: 2"
    assert html =~ "text-error"
  end

  test "the beacon shows the last sync and its errors", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"pulls" => 1, "errors" => 2})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "Com erros"
    assert html =~ "2 erros"
  end

  test "the activity panel shows the recorded events", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"pulls" => 8})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Atividade"
    assert html =~ "sync"
    assert html =~ "pulls: 8"
  end

  test "repository form recovery does not close the current panel", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "recovery")
    {:ok, view, _html} = live(conn, "/?repo=fixture/recovery&panel=intake")
    view |> element("#repo-select") |> render_change(%{"repo" => "fixture/recovery"})
    refute_patched(view)
    assert has_element?(view, "#board-page[data-panel=intake]")
  end

  test "panels are URL state and malformed conversation links cannot open another repo's task", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "panels")
    {:ok, other} = Board.add_repository("fixture", "other")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: other.id,
        kind: "issue",
        number: 1,
        title: "Other repo",
        state: "queued"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/?repo=fixture/panels&panel=conversation&task=#{task.id}")
    refute has_element?(view, "#conversation")
    assert has_element?(view, "#board-page[data-panel='']")

    render_patch(view, "/?repo=fixture/panels&panel=conversation&task=invalid")
    refute has_element?(view, "#conversation")
    view |> element("#board-settings") |> render_click()
    view |> element(".settings-nav__item[phx-value-section=inspect]") |> render_click()
    view |> element("#open-ai") |> render_click()
    assert_patch(view, "/?panel=ai&repo=fixture%2Fpanels")
    assert has_element?(view, "#board-page[data-panel=ai]")

    render_patch(view, "/?repo=#{repo.owner}/#{repo.name}")
    assert has_element?(view, "#board-page[data-panel='']")
  end

  test "closing the conversation hides the panel", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 89,
      title: "Close me",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("[data-task]") |> render_click()
    assert has_element?(view, "#conversation")

    view |> element("#conversation button[aria-label='Fechar painel (Esc)']") |> render_click()
    refute has_element?(view, "#conversation")
  end

  test "two clients receive the same broadcast", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, first, _html} = live(conn, ~p"/")
    {:ok, second, _html} = live(build_conn(), ~p"/")

    allow_view(first)
    allow_view(second)

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 101,
      title: "Both clients see this",
      state: "queued"
    })
    |> Repo.insert!()

    Board.broadcast(repo.id)

    assert render(first) =~ "Both clients see this"
    assert render(second) =~ "Both clients see this"
  end

  test "the speak event pushes the summary", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, view, _html} = live(conn, ~p"/?panel=settings")
    view |> element(".settings-nav__item[phx-value-section=voice]") |> render_click()

    view |> element("button", "Falar status") |> render_click()

    assert_push_event(view, "speak", %{text: text, lang: "pt-BR"})
    assert String.length(text) > 10
  end

  test "switching repositories closes the previous conversation", %{conn: conn} do
    {:ok, first} = Board.add_repository("fixture", "first")
    {:ok, _} = Board.add_repository("fixture", "second")

    %Task{}
    |> Task.changeset(%{repository_id: first.id, title: "Old context", number: 88})
    |> Repo.insert!()

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/first")
    view |> element("[data-task]") |> render_click()
    assert has_element?(view, "#conversation")

    view |> element("#repo-select") |> render_change(%{"repo" => "fixture/second"})

    refute has_element?(view, "#conversation")
    refute has_element?(view, "#ask-agent")
  end

  test "broadcast refreshes the open conversation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "conversation")

    task =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, title: "Fresh comments", number: 89})
      |> Repo.insert!()

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/conversation")
    view |> element("[data-task]") |> render_click()

    Board.upsert_comment(
      task,
      %{"id" => 42, "user" => %{"login" => "agent"}, "body" => "New evidence"},
      "agent"
    )

    send(view.pid, :board_updated)

    assert render(view) =~ "New evidence"
  end

  test "opening a task shows the conversation panel", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 88,
      title: "Open me",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("[data-task]") |> render_click()

    assert has_element?(view, "#conversation")
    assert has_element?(view, "#conversation", "Sem conversa nesta tarefa.")
  end

  test "the network buttons disable while the request is in flight", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "phx-disable-with"
    assert html =~ "Enviando"
    view |> element("#board-settings") |> render_click()
    view |> element(".settings-nav__item[phx-value-section=repositories]") |> render_click()
    assert render(view) =~ "Adicionar projeto"
  end
end

defmodule AgentBoardWeb.BoardShellTest do
  @moduledoc "The redesign shell: rail marks, freshness and the reconnect notice."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}

  test "the rail shows the attention marks of the current repository", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "rail")
    Board.log_event(repo.id, "sync", "sallaumen/rail", %{"errors" => 0})
    insert_task(repo, 1, "running")
    insert_task(repo, 2, "ready")
    insert_task(repo, 3, "blocked")
    insert_merged(repo, 4, "failure")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/rail")
    current = "button.ab-repo[aria-current=true]"

    assert has_element?(view, current <> " .ab-repo__n--you", "1")
    assert has_element?(view, current <> " .ab-repo__n--halt", "1")
    assert has_element?(view, current <> " .ab-g--run")
  end

  test "a review need opens directly on the PR tab", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "review-tab")
    Board.log_event(repo.id, "sync", "sallaumen/review-tab", %{"errors" => 0})
    task = insert_task(repo, 1, "ready")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/review-tab")

    view |> element("#task-#{task.id}") |> render_click()

    assert has_element?(view, "#conversation .ab-tab[aria-selected=true]", "PR")
  end

  test "a reconnect refreshes without a notice", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "reconnect")
    Board.log_event(repo.id, "sync", "sallaumen/reconnect", %{"errors" => 0})
    insert_task(repo, 1, "ready")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/reconnect")

    task = insert_task(repo, 2, "running")
    render_hook(view, "board_reconnected", %{})

    refute has_element?(view, ".ab-toast")
    assert has_element?(view, "#task-#{task.id}")
  end

  test "a frozen board shows the saved-data banner and stops calling itself live", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "frozen")
    Board.log_event(repo.id, "sync_error", "sallaumen/frozen", %{"reason" => "offline"})

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/frozen")

    assert has_element?(view, ".ab-beacon[data-state=offline]", "Sem conexão")
    assert has_element?(view, "#board-page[data-frozen=true]")
    assert has_element?(view, ".ab-frozen", "Tentar agora")
  end

  test "offline shows minimum counts and absolute ages", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "offline-honest")
    Board.log_event(repo.id, "sync", "fixture/offline-honest", %{"errors" => 0})
    Board.log_event(repo.id, "sync_error", "fixture/offline-honest", %{"reason" => "offline"})
    insert_task(repo, 1, "queued")
    at = Board.sync_snapshot(repo).last_success.inserted_at
    expected = AgentBoard.Time.local_time(at, 0)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/offline-honest")

    assert has_element?(view, "#sec-queue .ab-sec__count", "≥1")
    assert has_element?(view, "#sec-queue .ab-row", expected)
    refute has_element?(view, "#sec-queue .ab-row", "há ")
  end

  test "the beacon only says live when GitHub and the runner answered", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "fresh")
    Board.log_event(repo.id, "sync", "sallaumen/fresh", %{"errors" => 0})

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/fresh")

    assert has_element?(view, ".ab-beacon[data-state=live]", "Ao vivo")
    assert has_element?(view, ".ab-sync-pop", "Processo do agente")
    assert has_element?(view, ".ab-sync-pop", "Fila local")
  end

  defp insert_task(repo, number, state) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: "Task #{number}",
      state: state
    })
    |> Repo.insert!()
  end

  defp insert_merged(repo, number, checks) do
    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: number,
      title: "PR #{number}",
      state: "merged",
      merged_at: DateTime.utc_now(),
      checks_state: checks
    })
    |> Repo.insert!()
  end
end

defmodule AgentBoardWeb.ReconnectSinceTest do
  @moduledoc "A reconnect after the LiveView process is gone still counts stored changes."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  test "a reconnect after the frozen time refreshes without a notice", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "reconnect-since")
    Board.log_event(repo.id, "sync", "fixture/reconnect-since", %{"errors" => 0})

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/reconnect-since")
    since = DateTime.utc_now() |> DateTime.add(-2, :second)

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 1,
        title: "Arrived while away",
        state: "queued",
        state_changed_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    render_hook(view, "board_reconnected", %{"since" => DateTime.to_iso8601(since)})

    refute has_element?(view, ".ab-toast")
    assert has_element?(view, "#task-#{task.id}")
  end
end
