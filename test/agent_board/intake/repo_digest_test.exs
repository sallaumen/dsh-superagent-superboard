defmodule AgentBoard.Intake.RepoDigestTest do
  @moduledoc "What the split may know about the repository, bounded and never required."
  use ExUnit.Case, async: true

  alias AgentBoard.Intake.RepoDigest

  @repository %{owner: "o", name: "r"}

  defp client(plug), do: Req.new(base_url: "https://api.github.com", plug: plug, retry: false)

  defp blob(path), do: %{"path" => path, "type" => "blob"}

  defp doc(text), do: %{"content" => Base.encode64(text) <> "\n", "encoding" => "base64"}

  defp github(paths, docs) do
    client(fn conn ->
      case conn.request_path do
        "/repos/o/r/git/trees/HEAD" ->
          Req.Test.json(conn, %{"tree" => Enum.map(paths, &blob/1), "truncated" => false})

        "/repos/o/r/contents/" <> name when is_map_key(docs, name) ->
          Req.Test.json(conn, doc(docs[name]))

        _ ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
      end
    end)
  end

  test "the digest holds the code paths and the project's own documents" do
    digest =
      RepoDigest.read(
        @repository,
        github(
          ["lib/app/brand_live.ex", "deps/x/y.ex", "assets/logo.png", "mix.lock"],
          %{"AGENTS.md" => "Use LiveView."}
        )
      )

    assert digest =~ "lib/app/brand_live.ex"
    assert digest =~ "Use LiveView."
    refute digest =~ "deps/x/y.ex"
    refute digest =~ "logo.png"
    refute digest =~ "mix.lock"
  end

  test "a huge repository is bounded, the shallow paths first" do
    deep = for n <- 1..20_000, do: "lib/a/b/c/d/file_#{n}.ex"

    digest = RepoDigest.read(@repository, github(deep ++ ["lib/router.ex"], %{}))

    assert digest =~ "lib/router.ex"
    assert String.length(digest) < 40_000
  end

  test "a long document is cut, not dropped" do
    digest =
      RepoDigest.read(
        @repository,
        github(["a.ex"], %{"README.md" => String.duplicate("x", 50_000)})
      )

    assert digest =~ "README.md"
    assert String.length(digest) < 40_000
  end

  test "a repository the board cannot read is no digest, not a failure" do
    down = client(fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert RepoDigest.read(@repository, down) == nil
  end
end
