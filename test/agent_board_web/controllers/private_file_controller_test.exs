defmodule AgentBoardWeb.PrivateFileControllerTest do
  @moduledoc "A private context's images reach the board's own page, and nothing else does."
  use AgentBoardWeb.ConnCase, async: true

  alias AgentBoard.Board.PrivateContext
  alias AgentBoard.Board.Repository
  alias AgentBoard.Repo

  setup do
    repo = Repo.insert!(%Repository{id: 2_147_483_649, owner: "fixture", name: "private-files"})
    dir = PrivateContext.issue_dir(4)
    {:ok, _} = PrivateContext.put_file(repo, dir, "tela.png", "PNGDATA", "before")
    :ok = PrivateContext.write_note(repo, dir, "senha: hunter2")
    %{repo: repo, dir: dir}
  end

  test "a raster image is served with a literal type and no cache", %{conn: conn} = c do
    conn = get(conn, "/private/#{c.repo.id}/#{c.dir}/files/before--tela.png")

    assert response(conn, 200) == "PNGDATA"
    assert response_content_type(conn, :png) =~ "image/png"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "the note, a made-up folder or a path that climbs is a 404", %{conn: conn} = c do
    for path <- [
          "/private/#{c.repo.id}/#{c.dir}/notes.md",
          "/private/#{c.repo.id}/req-zz/files/before--tela.png",
          "/private/#{c.repo.id}/#{c.dir}/files/..%2F..%2Fnotes.md",
          "/private/#{c.repo.id}/#{c.dir}/..",
          "/private/#{c.repo.id}/#{c.dir}",
          "/private/999999/#{c.dir}/files/before--tela.png",
          "/private/9223372036854775808/#{c.dir}/files/before--tela.png",
          "/private/x/#{c.dir}/files/before--tela.png"
        ] do
      assert build_conn() |> get(path) |> response(404) == "", path
    end

    refute response(get(conn, "/private/#{c.repo.id}/#{c.dir}/notes.md"), 404) =~ "hunter2"
  end

  test "another site cannot read it", c do
    conn =
      build_conn()
      |> put_req_header("sec-fetch-site", "cross-site")
      |> get("/private/#{c.repo.id}/#{c.dir}/files/before--tela.png")

    assert conn.status == 403
  end
end
