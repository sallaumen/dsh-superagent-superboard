defmodule AgentBoard.RequestReceiptTest do
  @moduledoc "A real checkout without the SQL Sandbox's implicit outer transaction."
  use ExUnit.Case, async: false

  alias AgentBoard.Board.{Repository, Requests, Task}
  alias AgentBoard.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "one remote create finishes the reservation and a repeat returns the linked issue" do
    Sandbox.unboxed_run(Repo, fn ->
      repo = Repo.insert!(%Repository{owner: "receipt-test", name: Ecto.UUID.generate()})

      try do
        parent = Repo.insert!(%Task{repository_id: repo.id, title: "Parent", number: 388})

        Req.Test.stub(__MODULE__, fn conn ->
          send(self(), :posted)
          Req.Test.json(conn, %{number: 469, html_url: "https://example.invalid/issues/469"})
        end)

        client = Req.new(plug: {Req.Test, __MODULE__}, base_url: "https://example.invalid")

        request = %{
          key: "fixture",
          title: "Fixture",
          body: "Decision",
          blocker_for_task_id: parent.id
        }

        assert {:ok, task, :created} = Requests.create_request(repo, request, client)
        assert task.number == 469 and task.blocker_for_task_id == parent.id
        assert {:ok, ^task, :existing} = Requests.create_request(repo, request, client)
        assert_received :posted
        refute_received :posted
      after
        Repo.delete!(repo)
      end
    end)
  end
end
