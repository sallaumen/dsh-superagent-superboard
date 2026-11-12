defmodule AgentBoardWeb.SuperagentPanelControllerTest do
  @moduledoc "The signed-in panel address goes to a local browser, from the agent's own log, and nowhere else."
  # The folder of the agents' logs is one application setting.
  use AgentBoardWeb.ConnCase, async: false

  alias AgentBoard.{Board, Superagents}
  alias AgentBoardWeb.SuperagentPanelController

  @projects "/?panel=settings&section=projects"

  setup %{conn: conn} do
    home = Path.join(System.tmp_dir!(), "dsh-home-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(home, ".artifacts"))
    previous = Application.get_env(:agent_board, :dsh_superagent_home)
    Application.put_env(:agent_board, :dsh_superagent_home, home)

    on_exit(fn ->
      Application.put_env(:agent_board, :dsh_superagent_home, previous)
      File.rm_rf!(home)
    end)

    {:ok, repo} = Board.add_repository("fixture", "panel-link")

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-link",
        port: 3196,
        state_dir: "/tmp/superagent-link"
      })

    %{conn: %{conn | host: "localhost"}, home: home, superagent: superagent}
  end

  # A log the manager wrote `age` seconds ago.
  defp log!(home, name, lines, age) do
    path = Path.join([home, ".artifacts", name])
    File.write!(path, Enum.join(lines, "\n") <> "\n")
    File.touch!(path, System.os_time(:second) - age)
  end

  defp open(conn, superagent), do: post(conn, ~p"/superagents/#{superagent.id}/panel")

  test "a local browser is sent to the last address of the agent's newest log",
       %{conn: conn, home: home, superagent: superagent} do
    log!(
      home,
      "dsh-superagent-superagent-link-20261101-1.log",
      ["dsh web: http://127.0.0.1:3196/?token=first"],
      600
    )

    log!(
      home,
      "dsh-superagent-superagent-link-20261102-1.log",
      [
        "starting",
        "dsh web: http://127.0.0.1:3196/?token=second",
        "dsh web: http://127.0.0.1:3196/?token=third"
      ],
      60
    )

    # Another agent whose profile starts with the same letters, written last.
    log!(
      home,
      "dsh-superagent-superagent-link-two-20261103-1.log",
      ["dsh web: http://127.0.0.1:3197/?token=other"],
      1
    )

    conn = open(conn, superagent)

    assert redirected_to(conn, 303) == "http://127.0.0.1:3196/?token=third"
  end

  test "an address that is not this agent's panel on this machine opens nothing",
       %{conn: conn, home: home, superagent: superagent} do
    for address <- [
          "http://127.0.0.1:9999/?token=x",
          "https://example.test:3196/?token=x",
          "not an address"
        ] do
      log!(home, "dsh-superagent-superagent-link-20261102-1.log", ["dsh web: " <> address], 60)

      conn = open(conn, superagent)

      assert redirected_to(conn) == @projects
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "não é o painel deste agente"
    end
  end

  test "only this machine's browser, on a local name, counts as local" do
    assert SuperagentPanelController.local?({127, 0, 0, 1}, "localhost")
    assert SuperagentPanelController.local?({0, 0, 0, 0, 0, 0, 0, 1}, "[::1]")
    assert SuperagentPanelController.local?({127, 0, 0, 1}, "board.localhost")
    refute SuperagentPanelController.local?({192, 168, 0, 9}, "localhost")
    # Behind a proxy every request comes from this machine; the name tells.
    refute SuperagentPanelController.local?({127, 0, 0, 1}, "board.example.test")
  end

  test "a browser on another machine gets no address",
       %{conn: conn, home: home, superagent: superagent} do
    log!(
      home,
      "dsh-superagent-superagent-link-20261102-1.log",
      ["dsh web: http://127.0.0.1:3196/?token=secret"],
      60
    )

    conn = open(%{conn | remote_ip: {192, 168, 0, 9}}, superagent)

    assert redirected_to(conn) == @projects
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "na máquina onde o agente roda"
    refute inspect(conn.resp_headers) =~ "secret"
  end

  test "an agent with no log, or a log with no address, says so",
       %{conn: conn, home: home, superagent: superagent} do
    assert conn |> open(superagent) |> redirected_to() == @projects

    log!(home, "dsh-superagent-superagent-link-20261102-1.log", ["starting"], 60)
    conn = open(conn, superagent)

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "ainda não tem o endereço do painel"
  end

  test "a project that no longer has an agent says so", %{conn: conn} do
    conn = post(conn, ~p"/superagents/0/panel")

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "não tem mais agente"
  end
end
