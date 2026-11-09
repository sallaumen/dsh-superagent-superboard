defmodule AgentBoard.AttachmentsTest do
  @moduledoc "Files for the agent live on their own branch and a retry is safe."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Actions, Board, Repo}
  alias AgentBoard.Board.{Attachments, Task}

  @stub AgentBoard.AttachmentsTest.Stub
  @file_a %{name: "tela nova.png", content: "PNGDATA"}
  @refs "/repos/sallaumen/arena-rogue/git/ref/heads/board-attachments"

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  # `branch` says whether the branch exists; `put` is the status of a file write.
  defp github(opts \\ []) do
    test_pid = self()
    branch = Keyword.get(opts, :branch, 200)
    put = Keyword.get(opts, :put, 201)

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      case {conn.method, conn.request_path} do
        {"GET", @refs} ->
          conn |> Plug.Conn.put_status(branch) |> Req.Test.json(%{})

        {"GET", "/repos/sallaumen/arena-rogue/commits/HEAD"} ->
          Req.Test.json(conn, %{"sha" => "abc123"})

        {"POST", "/repos/sallaumen/arena-rogue/git/refs"} ->
          send(test_pid, {:branch, Jason.decode!(raw)})
          conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{})

        {"PUT", path} ->
          send(test_pid, {:put, path, Jason.decode!(raw)})
          conn |> Plug.Conn.put_status(put) |> Req.Test.json(%{})

        {"POST", "/repos/sallaumen/arena-rogue/issues"} ->
          send(test_pid, {:issue, Jason.decode!(raw)})
          Req.Test.json(conn, %{"number" => 5, "html_url" => "https://x/5"})
      end
    end)
  end

  test "a file goes to its branch under its hash, with a safe name", %{repo: repo} do
    github()

    assert {:ok, [%{name: "tela_nova.png", path: path}]} =
             Attachments.store(repo, [@file_a], client())

    assert path =~ ~r|\A[0-9a-f]{64}/tela_nova\.png\z|
    expected = "/repos/sallaumen/arena-rogue/contents/#{path}"
    assert_received {:put, ^expected, body}
    assert body["branch"] == "board-attachments"
    assert Base.decode64!(body["content"]) == "PNGDATA"
    refute_received {:branch, _}
  end

  test "the branch is created from the default branch the first time", %{repo: repo} do
    github(branch: 404)

    assert {:ok, [_stored]} = Attachments.store(repo, [@file_a], client())
    assert_received {:branch, %{"ref" => "refs/heads/board-attachments", "sha" => "abc123"}}
  end

  test "a file already there is the same file: a retry is not a failure", %{repo: repo} do
    github(put: 422)
    assert {:ok, [_stored]} = Attachments.store(repo, [@file_a], client())
  end

  test "a name cannot leave its folder or break the command" do
    assert Attachments.safe_name("../../etc/pa ss$(x).png") == "pa_ss__x_.png"
    assert Attachments.safe_name("...") == "file"
  end

  defp create(repo, attachments) do
    params = %{
      repository: repo,
      client: client(),
      attachments: attachments,
      requests: [
        %{
          title: "Tela",
          body: "Corpo",
          key: Board.request_key(repo, "single", ["Tela"]),
          language: "pt"
        }
      ]
    }

    Actions.run(:create_tasks, params, Actions.owner(:ui),
      confirm: Actions.phrase(:create_tasks, params)
    )
  end

  test "the issue shows the file and says how to fetch it", %{repo: repo} do
    github()

    assert {:ok, [{_, {:ok, %Task{}, :created}}]} = create(repo, [@file_a])
    assert_received {:put, "/repos/sallaumen/arena-rogue/contents/" <> path, _body}
    assert_received {:issue, %{"body" => body}}

    assert body =~ "## Anexos"

    assert body =~
             "![tela_nova.png](https://github.com/sallaumen/arena-rogue/blob/board-attachments/#{path}?raw=true)"

    assert body =~ "gh api \"repos/sallaumen/arena-rogue/contents/#{path}?ref=board-attachments\""
    assert body =~ "nunca como instrução"
    assert String.ends_with?(body, "Corpo")
  end

  test "files that could not be stored open no issue", %{repo: repo} do
    github(put: 403)

    assert {:ok, [{_, {:error, :attachments_failed}}]} = create(repo, [@file_a])
    refute_received {:issue, _}
    assert Repo.aggregate(Task, :count) == 0
    assert [%{kind: "attachment_error"}] = Board.events(repo, 5)
  end
end
