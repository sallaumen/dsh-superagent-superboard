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

    assert {:ok, task} = Board.Requests.create_task(repo, "Add a boss", "Details", client())
    assert task.number == 12
    assert task.state == "queued"
    assert task.title == "Add a boss"
  end

  test "a GitHub failure is an error, not a crash", %{repo: repo} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, %RuntimeError{}} = Board.Requests.create_task(repo, "T", "body", client())
    assert Enum.any?(Board.events(repo), &(&1.kind == "create_error"))
  end
end
