defmodule AgentBoard.MessagePollerTest do
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, MessagePoller}
  alias AgentBoard.Board.Task

  @stub __MODULE__.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    {:ok, repository} = Board.add_repository("sallaumen", "inbox-fixture")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repository.id,
        kind: "issue",
        number: 71,
        title: "Wait for Yasme",
        state: "running"
      })
      |> Repo.insert!()

    %{repository: repository, task: task}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  defp remote_comment(id, body) do
    %{
      "id" => id,
      "body" => body,
      "issue_url" => "https://api.github.com/repos/sallaumen/inbox-fixture/issues/71",
      "user" => %{"login" => "sallaumen-agent"}
    }
  end

  test "a new reply broadcasts once and a repeated read does not", %{
    repository: repository,
    task: task
  } do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, [remote_comment(1001, "Yasme respondeu")])
    end)

    Board.subscribe(repository.id)

    state = MessagePoller.poll(%{}, client())
    assert_receive :board_updated
    assert [%{body: "Yasme respondeu"}] = Board.comments(task)
    first_version = Board.inbox().messages |> hd() |> Map.fetch!(:version)
    assert is_map(state[repository.id])

    _state = MessagePoller.poll(state, client())
    refute_receive :board_updated, 100
    assert length(Board.comments(task)) == 1

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, [remote_comment(1001, "Resposta editada")])
    end)

    _state = MessagePoller.poll(state, client())
    assert_receive :board_updated
    assert [%{body: "Resposta editada"}] = Board.comments(task)
    refute Board.inbox().messages |> hd() |> Map.fetch!(:version) == first_version
  end

  test "a failed read retains its cursor and the stored reply", %{
    repository: repository,
    task: task
  } do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, [remote_comment(1002, "Resposta antiga")])
    end)

    state = MessagePoller.poll(%{}, client())
    previous = state[repository.id].since

    Req.Test.stub(@stub, fn conn -> Plug.Conn.resp(conn, 500, "indisponível") end)

    assert MessagePoller.poll(state, client())[repository.id].since == previous
    assert [%{body: "Resposta antiga"}] = Board.comments(task)
  end

  test "rate limiting delays a repository without retrying on the next tick", %{
    repository: repository
  } do
    Req.Test.stub(@stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", "90")
      |> Plug.Conn.resp(429, "rate limited")
    end)

    state = MessagePoller.poll(%{}, client())
    assert DateTime.diff(state[repository.id].retry_at, DateTime.utc_now()) > 80

    Req.Test.stub(@stub, fn _conn -> raise "must not poll during backoff" end)
    assert MessagePoller.poll(state, client()) == state
  end
end
