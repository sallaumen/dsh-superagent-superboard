defmodule AgentBoardWeb.SettingsSetupTest do
  @moduledoc "Settings → AI and setup: who does what, and a check on the owner's click."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  setup do
    previous = Application.get_env(:agent_board, :setup_readers)
    on_exit(fn -> restore(previous) end)

    test = self()

    Application.put_env(:agent_board, :setup_readers,
      config: [
        github: fn -> true end,
        agents: fn -> [%{repository: "sallaumen/arena-rogue", model: "deepseek-flash"}] end,
        cli: fn _executor -> true end,
        board_ai: fn -> %{provider: :deepseek, model: "deepseek-flash", fallbacks: [:gemini]} end,
        voice: fn -> false end
      ],
      live: [
        github: fn -> {:error, {:http, 401}} end,
        agents: fn ->
          send(test, :checked)
          [%{repository: "sallaumen/arena-rogue", model: "deepseek-flash", answer: :ok}]
        end,
        cli: fn
          "codex" -> {:error, :logged_out}
          _ -> :ok
        end,
        board_ai: fn -> %{provider: :deepseek, model: "deepseek-flash", fallbacks: [:gemini]} end,
        provider_check: fn :deepseek -> :ok end,
        voice: fn -> {:error, :not_configured} end
      ]
    )

    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    :ok
  end

  defp restore(nil), do: Application.delete_env(:agent_board, :setup_readers)
  defp restore(value), do: Application.put_env(:agent_board, :setup_readers, value)

  test "the first section says which AI does what, in three classes, before any check", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/?repo=sallaumen/arena-rogue&panel=settings&section=setup")

    assert has_element?(
             view,
             ".settings-nav__item:first-child[phx-value-section=setup]",
             "IAs e setup"
           )

    assert has_element?(view, "#setup-class-work h4", "Quem faz o trabalho")
    assert has_element?(view, "#setup-class-board_ai h4", "A IA do próprio board")
    assert has_element?(view, "#setup-class-voice h4", "Voz")

    # Without a click nothing is proved: a key that is set is only configured.
    assert has_element?(view, "#setup-row-github[data-state=configured]")
    assert has_element?(view, "#setup-row-board_ai", "DeepSeek responde (deepseek-flash)")
    assert has_element?(view, "#setup-row-codex", "Codex")
    assert has_element?(view, "#setup-row-voice[data-state=off]")
    refute_received :checked
  end

  test "a closed Settings reads nothing; each opening reads the configuration once", %{
    conn: conn
  } do
    test = self()
    readers = Application.get_env(:agent_board, :setup_readers)

    Application.put_env(
      :agent_board,
      :setup_readers,
      Keyword.update!(readers, :config, fn config ->
        Keyword.put(config, :github, fn ->
          send(test, :config_read)
          true
        end)
      end)
    )

    {:ok, view, _html} = live(conn, "/?repo=sallaumen/arena-rogue")
    refute_received :config_read

    render_patch(view, "/?repo=sallaumen/arena-rogue&panel=settings&section=projects")
    assert_received :config_read
    flush(:config_read)

    # Moving between sections of an open panel is not a new opening.
    render_patch(view, "/?repo=sallaumen/arena-rogue&panel=settings&section=execution")
    refute_received :config_read

    render_patch(view, "/?repo=sallaumen/arena-rogue")
    render_patch(view, "/?repo=sallaumen/arena-rogue&panel=settings&section=projects")
    assert_received :config_read
  end

  defp flush(message) do
    receive do
      ^message -> flush(message)
    after
      0 -> :ok
    end
  end

  test "the check proves each part and points to the next step", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?repo=sallaumen/arena-rogue&panel=settings&section=setup")

    view |> element("#setup-check") |> render_click()
    render_async(view, 2_000)
    assert_received :checked

    assert has_element?(view, "#setup-row-github[data-state=failed]", "recusou o token")
    assert has_element?(view, "#setup-row-board_ai[data-state=ok]")
    assert has_element?(view, "#setup-row-codex[data-state=failed] code", "codex login")

    # The next step lives on its own row; the top only points to it.
    assert has_element?(
             view,
             "#setup-row-github[data-next] a[href='https://github.com/settings/tokens']",
             "Criar um token"
           )

    assert has_element?(view, "a.setup__jump[href='#setup-row-github']", "GitHub")
    # One fix button for GitHub, not a second copy at the top.
    setup = view |> element(".setup") |> render()
    assert length(String.split(setup, "Criar um token")) == 2
  end

  test "a fresh tab restores the last successful check and a later failure keeps its date", %{
    conn: conn
  } do
    url = "/?repo=sallaumen/arena-rogue&panel=settings&section=setup"
    readers = Application.fetch_env!(:agent_board, :setup_readers)

    passing =
      Keyword.update!(readers, :live, fn live ->
        Keyword.merge(live, github: fn -> {:ok, "octo"} end, cli: fn _ -> :ok end)
      end)

    Application.put_env(:agent_board, :setup_readers, passing)
    {:ok, first, _} = live(conn, url)
    first |> element("#setup-check") |> render_click()
    render_async(first, 2_000)
    assert_received :checked
    assert has_element?(first, "#setup-last-check", "OK")
    [passed_at] = first |> element("#setup-last-check time") |> render() |> datetime_values()

    # The current GitHub token is gone. A fresh tab must show that and the
    # previous success, without contacting a single provider on open.
    Application.put_env(
      :agent_board,
      :setup_readers,
      Keyword.update!(readers, :config, &Keyword.put(&1, :github, fn -> false end))
    )

    {:ok, reopened, _} = live(conn, url)
    assert has_element?(reopened, "#setup-row-github[data-state=missing]")
    assert has_element?(reopened, "#setup-last-check time[datetime='#{passed_at}']")
    assert has_element?(reopened, "#setup-last-check", "OK")
    refute_received :checked

    reopened |> element("#setup-check") |> render_click()
    render_async(reopened, 2_000)
    assert_received :checked
    assert has_element?(reopened, "#setup-row-github[data-state=failed]")

    render_patch(reopened, "/?repo=sallaumen/arena-rogue")
    render_patch(reopened, url)

    [failed_at, ^passed_at] =
      reopened |> element("#setup-last-check") |> render() |> datetime_values()

    refute failed_at == passed_at
    refute_received :checked
  end

  defp datetime_values(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("time")
    |> LazyHTML.attribute("datetime")
  end

  test "with a required part missing, Settings opens on AI and setup and marks it", %{conn: conn} do
    Application.put_env(:agent_board, :setup_readers,
      config: [
        github: fn -> false end,
        agents: fn -> [] end,
        cli: fn _executor -> false end,
        board_ai: fn -> %{provider: :deepseek, model: "deepseek-flash", fallbacks: []} end,
        voice: fn -> false end
      ]
    )

    {:ok, view, _html} = live(conn, "/?repo=sallaumen/arena-rogue&panel=settings")

    assert has_element?(view, ".settings-nav__item.is-current[phx-value-section=setup]")

    assert has_element?(
             view,
             ".settings-nav__item[phx-value-section=setup] .settings-nav__mark--halt"
           )

    assert has_element?(view, "#setup-row-github[data-next]")
    assert has_element?(view, "a.setup__jump[href='#setup-row-github']", "GitHub")
  end

  test "with everything set, Settings opens where it always did", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?repo=sallaumen/arena-rogue&panel=settings")

    assert has_element?(view, ".settings-nav__item.is-current[phx-value-section=projects]")

    refute has_element?(
             view,
             ".settings-nav__item[phx-value-section=setup] .settings-nav__mark--halt"
           )
  end
end
