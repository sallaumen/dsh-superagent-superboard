defmodule AgentBoard.ProjectMergePolicyTest do
  use ExUnit.Case, async: true
  alias AgentBoard.ProjectMergePolicy, as: Policy

  @repo %{owner: "fixture", name: "game"}
  @sha String.duplicate("a", 40)

  defp github(status, document) do
    Req.Test.stub(__MODULE__, fn conn ->
      response =
        case conn.request_path do
          "/repos/fixture/game" ->
            {200, %{"default_branch" => "release/next"}}

          "/repos/fixture/game/git/ref/heads/release/next" ->
            {200, %{"object" => %{"sha" => @sha}}}

          "/repos/fixture/game/contents/.github/superboard-merge.json" ->
            assert URI.decode_query(conn.query_string)["ref"] == @sha

            {status,
             %{"encoding" => "base64", "content" => Base.encode64(Jason.encode!(document))}}
        end

      {code, body} = response
      conn |> Plug.Conn.put_status(code) |> Req.Test.json(body)
    end)

    Req.new(plug: {Req.Test, __MODULE__})
  end

  test "reads by branch revision and describes the exact checks without running commands" do
    policy = %{
      "method" => "merge",
      "review" => true,
      "local" => %{"Unit" => ["not-an-executable"]},
      "github" => ["ci/quality"]
    }

    result = Policy.read(@repo, github(200, policy))
    assert result.branch == "release/next"
    assert result.sha == @sha

    assert result.result ==
             {:ok, %{"local" => ["Unit"], "github" => ["ci/quality"], "review" => true}}

    assert result.url =~ "/blob/#{@sha}/.github/superboard-merge.json"
  end

  test "does not present a missing, invalid, or unreadable policy as optional review" do
    assert Policy.read(@repo, github(404, nil)).result == :missing
    assert Policy.read(@repo, github(200, %{"review" => false})).result == :invalid
    assert Policy.read(@repo, github(403, nil)).result == :unavailable
    assert Policy.enforcement(nil, @repo) == :no_agent
  end
end
