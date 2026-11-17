defmodule AgentBoardWeb.PullEvidenceTest do
  use AgentBoardWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.Review
  @sha String.duplicate("a1", 20)

  test "automatic broadcast adds attributed reports to Merged and history without changing GitHub verdicts",
       %{conn: conn} do
    {:ok, repo} = Board.add_repository("example", "receipt-project")

    pull =
      Repo.insert!(%PullRequest{
        repository_id: repo.id,
        number: 42,
        title: "Clear choices",
        state: "merged",
        merged_at: DateTime.utc_now() |> DateTime.truncate(:second),
        head_sha: @sha,
        review_state: "none",
        checks_state: "none"
      })

    conn = Plug.Conn.put_req_header(conn, "cookie", "board_locale=en")
    {:ok, view, _} = live(conn, ~p"/?repo=example/receipt-project")
    assert has_element?(view, "#sec-log", "no CI")
    assert has_element?(view, "#sec-log", "no review")

    ci = %{
      "result" => "pass",
      "sha" => @sha,
      "author" => "maintainer",
      "commands" => ["make test"],
      "url" => "https://github.com/example/receipt-project/pull/42#issuecomment-1"
    }

    review = %{
      "result" => "approved",
      "sha" => @sha,
      "author" => "maintainer",
      "reviewer" => "independent agent",
      "url" => "https://github.com/example/receipt-project/pull/42#issuecomment-2"
    }

    pull
    |> Ecto.Changeset.change(reported_evidence: %{"ci" => ci, "review" => review})
    |> Repo.update!()

    send(view.pid, :board_updated)
    assert has_element?(view, "#sec-log", "Local CI reported: passed")
    assert has_element?(view, "#sec-log", "Independent review reported")
    assert has_element?(view, "#sec-log .ab-validation-sources", "GitHub review: no review")
    assert has_element?(view, "#sec-log .ab-validation-sources", "Reported by maintainer")
    assert has_element?(view, "#sec-log a[href$='issuecomment-1']", "Open source comment")
    assert has_element?(view, "#pull-#{pull.id}", "Independent review reported")
    assert Repo.get!(PullRequest, pull.id).review_state == "none"
  end

  test "native changes requested remains visible despite an independent approval report" do
    pull = %PullRequest{
      review_state: "changes_requested",
      head_sha: @sha,
      reported_evidence: %{"review" => %{"sha" => @sha, "result" => "approved"}}
    }

    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    assert Review.label(pull) == "changes requested"
  end
end
