# Isolated browser fixture. Run with MIX_ENV=test MIX_TEST_PARTITION=ui_review,
# PORT=4004 PHX_SERVER=1 elixir --sname board_ui_review -S mix run scripts/ui_review_fixture.exs
# The sandbox transaction rolls back when this task-owned process exits.
unless Mix.env() == :test and System.get_env("MIX_TEST_PARTITION") == "ui_review" do
  raise "UI fixtures require MIX_ENV=test and MIX_TEST_PARTITION=ui_review"
end

defmodule UIReviewFixture do
  import Ecto.Query
  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Task, Event}

  def seed do
    {:ok, repo} = Board.add_repository("ui-fixture", "read-only")

    for n <- 1..3 do
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: n,
        title: "Review fixture task #{n}",
        state: "queued",
        body: "Isolated test data; no GitHub requests."
      })
      |> Repo.insert!()
    end

    Board.log_event(repo.id, "sync", "ui-fixture/read-only", %{"errors" => 0})
    old = DateTime.add(DateTime.utc_now(), -600, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(e in Event, where: e.repository_id == ^repo.id), set: [inserted_at: old])
    repo.id
  end

  def broadcast do
    repo = Board.repository_by_slug("ui-fixture/read-only")
    Board.broadcast(repo.id)
  end

  def move do
    task = Repo.one!(from t in Task, where: t.number == 1)
    Repo.update!(Task.changeset(task, %{state: "running"}))
    broadcast()
  end
end

Application.ensure_all_started(:agent_board)
Ecto.Adapters.SQL.Sandbox.checkout(AgentBoard.Repo, ownership_timeout: :infinity)
Ecto.Adapters.SQL.Sandbox.mode(AgentBoard.Repo, {:shared, self()})
UIReviewFixture.seed()
File.mkdir_p!("tmp/review-round2")
File.write!("tmp/review-round2/fixture-node", Atom.to_string(node()))
IO.puts("UI fixture ready")
Process.sleep(:infinity)
