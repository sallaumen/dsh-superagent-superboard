defmodule AgentBoardWeb.ExecutorsTest do
  @moduledoc "O painel Executores e a aba Execuções: o livro de uso na tela, cada executor na sua moeda."
  use AgentBoardWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}

  @path "/?repo=fixture/executors&panel=settings&section=execution"

  setup do
    {:ok, repo} = Board.add_repository("fixture", "executors")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 7,
        title: "Mapa",
        body: "PR #3",
        state: "done"
      })
      |> Repo.insert!()

    Repo.update_all(
      from(t in Task, where: t.id == ^task.id),
      set: [inserted_at: DateTime.add(now, -3600, :second)]
    )

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 3,
      title: "Mapa",
      state: "merged",
      merged_at: now,
      head_ref: "feat/mapa",
      closes_issues: [7]
    })
    |> Repo.insert!()

    ledger("claude_code", "session-1", %{
      model: "claude-opus-5-5",
      cwd: "/tmp/executors",
      git_branch: "feat/mapa",
      input_tokens: 1_000_000,
      output_tokens: 1_000_000
    })

    ledger("dsh", "ticket-1", %{
      model: "deepseek-flash",
      cwd: "/tmp/executors",
      git_branch: "feat/mapa"
    })

    ledger("codex", "thread-1", %{model: "gpt-6-sol", cwd: "/tmp/executors"})

    Repo.insert_all("usage_limits", [
      %{
        source: "codex",
        limit_id: "codex",
        plan_type: "chatgpt",
        primary_used_percent: 90.0,
        primary_window_minutes: 10_080,
        observed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])

    %{repo: repo, task: task}
  end

  defp ledger(source, execution, attrs) do
    at = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("usage_ledger", [
      Map.merge(
        %{
          source: source,
          execution_id: execution,
          day: Date.utc_today(),
          cwd: "/tmp/executors",
          git_branch: nil,
          model: nil,
          requests: 10,
          input_tokens: 1_000_000,
          output_tokens: 1_000_000,
          cache_read_tokens: 0,
          cache_write_tokens: 0,
          first_at: at,
          last_at: at,
          inserted_at: at,
          updated_at: at
        },
        attrs
      )
    ])
  end

  test "o painel shows the three executors in their own currency and never sums them",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    claude = view |> element("#executor-claude_code") |> render()
    assert claude =~ "Claude Code"
    assert claude =~ "estimado"
    assert claude =~ "≈ US$"
    assert claude =~ "preço de lista"
    assert has_element?(view, "#executor-claude_code .ab-executor__bars")

    codex = view |> element("#executor-codex") |> render()
    assert codex =~ "Codex"
    assert codex =~ "medido"
    assert codex =~ "90%"
    assert has_element?(view, "#executor-codex [role=progressbar]")
    refute codex =~ "≈ US$"
    refute codex =~ "≥ US$"

    dsh = view |> element("#executor-dsh") |> render()
    assert dsh =~ "DeepSeek"
    assert dsh =~ "estimado"
    assert has_element?(view, "#executor-dsh .ab-executor__bars")
    assert has_element?(view, "#executor-dsh .ab-executor__limits-card", "cada projeto")

    refute has_element?(view, "#settings-execution", "Total geral")
  end

  test "the window switches between 7 and 30 days without leaving the section", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    assert has_element?(
             view,
             ~s(#settings-execution .ab-execution__range button[aria-pressed="true"][phx-value-days="7"])
           )

    view
    |> element(~s(#settings-execution .ab-execution__range button[phx-value-days="30"]))
    |> render_click()

    assert has_element?(
             view,
             ~s(#settings-execution .ab-execution__range button[aria-pressed="true"][phx-value-days="30"])
           )
  end

  test "a task's Execuções tab lists its ledger execution, attributed by the PR branch",
       %{conn: conn, task: task} do
    # The ledger is read when the tab opens: before that the tab shows no
    # count, never a zero nobody counted.
    {:ok, closed, _html} =
      live(conn, "/?repo=fixture/executors&panel=conversation&task=#{task.id}")

    refute has_element?(closed, "#inspector-tab-execucoes .ab-num")

    {:ok, view, _html} =
      live(conn, "/?repo=fixture/executors&panel=conversation&task=#{task.id}&tab=execucoes")

    assert has_element?(view, "#inspector-tab-execucoes .ab-num")
    panel = view |> element("#inspector-panel-execucoes") |> render()

    assert panel =~ "mesclado"
    assert panel =~ "Claude Code"
    assert panel =~ "claude-opus-5-5"
    assert panel =~ "lista"
    assert panel =~ "DeepSeek"
    # The Codex thread has no branch that closes a task: it is not guessed.
    refute has_element?(view, "#inspector-panel-execucoes .ab-exec-row__name", "Codex")
  end
end
