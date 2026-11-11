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

  test "the check proves each part and points to the next step", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?repo=sallaumen/arena-rogue&panel=settings&section=setup")

    view |> element("#setup-check") |> render_click()
    render_async(view, 2_000)
    assert_received :checked

    assert has_element?(view, "#setup-row-github[data-state=failed]", "recusou o token")
    assert has_element?(view, "#setup-row-board_ai[data-state=ok]")
    assert has_element?(view, "#setup-row-codex[data-state=failed] code", "codex login")

    assert has_element?(
             view,
             "#setup-next a[href='https://github.com/settings/tokens']",
             "Criar um token"
           )
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

    assert has_element?(view, "#setup-next", "GitHub")
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
