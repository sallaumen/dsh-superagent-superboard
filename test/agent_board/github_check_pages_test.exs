defmodule AgentBoard.GitHubCheckPagesTest do
  use ExUnit.Case, async: true
  alias AgentBoard.{GitHub, Sync}

  test "a failure on the second page defeats a hundred successful checks" do
    client = Req.new(base_url: "https://api.github.com", plug: {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/repos/org/game/commits/head/check-runs"

      case Plug.Conn.fetch_query_params(conn).query_params["page"] do
        "1" ->
          conn
          |> Plug.Conn.put_resp_header(
            "link",
            ~s(<https://api.github.com/check-runs?page=2>; rel="next")
          )
          |> Req.Test.json(%{
            "check_runs" =>
              List.duplicate(%{"conclusion" => "success", "status" => "completed"}, 100)
          })

        "2" ->
          Req.Test.json(conn, %{
            "check_runs" => [
              %{"name" => "release", "conclusion" => "failure", "status" => "completed"}
            ]
          })
      end
    end)

    checks = GitHub.check_runs(client, "org", "game", "head")
    assert length(checks) == 101
    assert Sync.checks_rollup(checks) == {"failure", "release"}
  end
end
