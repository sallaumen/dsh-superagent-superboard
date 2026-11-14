defmodule AgentBoard.CreateTaskTest do
  @moduledoc "Creating a task opens a GitHub issue and stores it locally."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Board

  @stub AgentBoard.CreateTaskTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  test "a created issue becomes a queued task", %{repo: repo} do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"number" => 12, "html_url" => "https://github.com/x/y/issues/12"})
    end)

    request = %{key: "boss", title: "Add a boss", body: "Details"}
    assert {:ok, task, :created} = Board.Requests.create_request(repo, request, client())
    assert task.number == 12
    assert task.state == "queued"
    assert task.title == "Add a boss"
  end

  test "an empty body stays a string in the issue even when the draft stores nil", %{repo: repo} do
    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert %{"body" => ""} = Jason.decode!(raw)
      Req.Test.json(conn, %{"number" => 12, "html_url" => "https://github.com/x/y/issues/12"})
    end)

    request = %{key: "empty-body", title: "Title alone", body: ""}
    assert {:ok, task, :created} = Board.Requests.create_request(repo, request, client())
    assert is_nil(task.body)
  end

  test "a GitHub failure is an error, not a crash", %{repo: repo} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, %AgentBoard.GitHub.HTTPError{status: 500}} =
             Board.Requests.create_request(
               repo,
               %{key: "fail", title: "T", body: "body"},
               client()
             )

    assert Enum.any?(Board.events(repo), &(&1.kind == "create_error"))
  end
end
