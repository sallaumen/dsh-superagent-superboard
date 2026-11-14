defmodule AgentBoardWeb.AttachmentControllerTest do
  @moduledoc "The board shows a private repository's images, and nothing else from it."
  use AgentBoardWeb.ConnCase, async: false

  alias AgentBoard.Board.Repository
  alias AgentBoard.Repo

  @stub AgentBoardWeb.AttachmentControllerTest.Stub
  @hash String.duplicate("a", 64)

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn -> Application.delete_env(:agent_board, :github_client) end)
    repo = Repo.insert!(%Repository{id: 2_147_483_648, owner: "sallaumen", name: "arena-rogue"})
    %{repo: repo}
  end

  defp github(status \\ 200) do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, {:github, conn.request_path, conn.query_string})
      Plug.Conn.send_resp(conn, status, "PNGDATA")
    end)
  end

  test "an image comes from the attachments branch", %{conn: conn, repo: repo} do
    github()

    conn = get(conn, "/attachments/#{repo.id}/#{@hash}/mock.png")

    assert response(conn, 200) == "PNGDATA"
    assert response_content_type(conn, :png) =~ "image/png"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

    path = "/repos/sallaumen/arena-rogue/contents/#{@hash}/mock.png"
    assert_received {:github, ^path, "ref=board-attachments"}
  end

  test "html and svg are never served from the board", %{conn: conn, repo: repo} do
    github()

    for name <- ["mock.html", "mock.svg"] do
      conn = get(conn, "/attachments/#{repo.id}/#{@hash}/#{name}")

      assert redirected_to(conn, 302) ==
               "https://github.com/sallaumen/arena-rogue/blob/board-attachments/#{@hash}/#{name}"
    end

    refute_received {:github, _, _}
  end

  test "a path that is not an attachment's asks GitHub nothing", %{conn: conn, repo: repo} do
    github()

    assert response(get(conn, "/attachments/#{repo.id}/abc/mock.png"), 404)
    assert response(get(conn, "/attachments/#{repo.id}/#{@hash}/..%2Fsecret.png"), 404)
    assert response(get(conn, "/attachments/#{repo.id}/#{@hash}/a%20b.png"), 404)
    assert response(get(conn, "/attachments/nope/#{@hash}/mock.png"), 404)
    assert response(get(conn, "/attachments/999999999/#{@hash}/mock.png"), 404)
    assert response(get(conn, "/attachments/9223372036854775808/#{@hash}/mock.png"), 404)
    refute_received {:github, _, _}
  end

  # Each image costs one GitHub call on the board's token: another site's page
  # full of <img> tags would burn the hourly quota.
  for site <- ["cross-site", "same-site"] do
    test "a #{site} image request asks GitHub nothing", %{conn: conn, repo: repo} do
      github()

      conn =
        conn
        |> put_req_header("sec-fetch-site", unquote(site))
        |> get("/attachments/#{repo.id}/#{@hash}/mock.png")

      assert conn.status == 403
      refute_received {:github, _, _}
    end
  end

  test "the board's own page still loads its images", %{conn: conn, repo: repo} do
    github()

    conn =
      conn
      |> put_req_header("sec-fetch-site", "same-origin")
      |> get("/attachments/#{repo.id}/#{@hash}/mock.png")

    assert response(conn, 200) == "PNGDATA"
  end

  test "a file GitHub does not have is a 404, not a crash", %{conn: conn, repo: repo} do
    github(404)
    assert response(get(conn, "/attachments/#{repo.id}/#{@hash}/mock.png"), 404)
  end
end
