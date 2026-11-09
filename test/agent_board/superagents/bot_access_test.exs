defmodule AgentBoard.Superagents.BotAccessTest do
  @moduledoc "Before a project is set up, the bot gets the access its source requires."
  use ExUnit.Case, async: false

  alias AgentBoard.Superagents.BotAccess

  @stub __MODULE__
  @repo %{owner: "fixture", name: "projeto"}

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    {:ok,
     client: Req.new(base_url: "https://api.github.test", plug: {Req.Test, @stub}, retry: false)}
  end

  defp stub(role, invite) do
    test = self()

    Req.Test.stub(@stub, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/repos/fixture/projeto/collaborators/robo/permission"} ->
          answer_role(conn, role)

        {"PUT", "/repos/fixture/projeto/collaborators/robo"} ->
          send(test, :invited)
          invite.(conn)
      end
    end)
  end

  defp answer_role(conn, nil), do: status(conn, 404)
  defp answer_role(conn, role), do: Req.Test.json(conn, %{"role_name" => role})

  defp status(conn, code) do
    conn |> Plug.Conn.put_status(code) |> Req.Test.json(%{"message" => "no"})
  end

  defp runner(answer \\ {"", 0}) do
    test = self()

    fn cli, args, opts ->
      send(test, {:ran, cli, args})
      send(test, {:env, opts[:env]})
      answer
    end
  end

  test "a bot that can write needs nothing", %{client: client} do
    stub("write", fn _conn -> flunk("must not invite") end)

    assert :ok = BotAccess.ensure(@repo, "robo", "/bin/gh-robo", client, runner())
    refute_received {:ran, _, _}
  end

  test "a bot that can only read is invited and accepts", %{client: client} do
    stub("read", &(&1 |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 77})))

    assert :ok = BotAccess.ensure(@repo, "robo", "/bin/gh-robo", client, runner())
    assert_received :invited

    assert_received {:ran, "/bin/gh-robo",
                     ["api", "--method", "PATCH", "user/repository_invitations/77"]}

    # The board's token must not stand in for the bot's login.
    assert_received {:env, env}
    assert {"GITHUB_TOKEN", nil} in env
    assert {"GH_TOKEN", nil} in env
  end

  test "an invitation GitHub says is unnecessary needs no acceptance", %{client: client} do
    stub("read", &Plug.Conn.send_resp(&1, 204, ""))

    assert :ok = BotAccess.ensure(@repo, "robo", "/bin/gh-robo", client, runner())
    refute_received {:ran, _, _}
  end

  test "an owner who cannot invite is told where to do it", %{client: client} do
    stub("read", &status(&1, 403))

    assert {:error, {:setup, text}} =
             BotAccess.ensure(@repo, "robo", "/bin/gh-robo", client, runner())

    assert text =~ "@robo"
    assert text =~ "https://github.com/fixture/projeto/settings/access"
  end

  test "an invitation the bot could not accept says so", %{client: client} do
    stub("read", &(&1 |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 77})))

    assert {:error, {:setup, text}} =
             BotAccess.ensure(@repo, "robo", "/bin/gh-robo", client, runner({"token secret", 1}))

    assert text =~ "@robo"
    refute text =~ "secret"
  end

  test "a bot account GitHub does not have", %{client: client} do
    stub(nil, fn _conn -> flunk("must not invite") end)

    assert {:error, {:setup, text}} =
             BotAccess.ensure(@repo, "robo", "/bin/gh-robo", client, runner())

    assert text =~ "@robo"
  end
end
