defmodule AgentBoard.PullEvidenceTest do
  use ExUnit.Case, async: true
  alias AgentBoard.PullEvidence
  @sha String.duplicate("a1", 20)
  @other String.duplicate("b2", 20)

  test "PR comment validation reaches local CI without a ticket or workpad" do
    pull = %AgentBoard.Board.PullRequest{
      number: 42,
      head_sha: @sha,
      reported_evidence: PullEvidence.parse([comment(1, validation())])
    }

    assert %{42 => %{state: :pass, scope: :pr_comment}} =
             AgentBoard.LocalCI.by_pr(%{owner: "example", name: "app"}, [], pulls: [pull])
  end

  test "reads local validation and an independent report on the same PR, retaining attribution" do
    evidence = PullEvidence.parse([comment(1, validation()), comment(2, review())])
    assert evidence["ci"]["result"] == "pass"
    assert evidence["ci"]["sha"] == @sha
    assert evidence["ci"]["author"] == "maintainer"
    assert evidence["ci"]["url"] =~ "#issuecomment-1"
    assert evidence["review"]["result"] == "approved"
    assert evidence["review"]["reviewer"] == "separate test-reviewer agent"
  end

  test "self review and ordinary discussion never become independent approval" do
    assert PullEvidence.parse([comment(1, validation())])["review"] == nil
    assert PullEvidence.parse([comment(1, "Approved head `#{@sha}`. Looks good")]) == %{}
    assert PullEvidence.parse([comment(1, "> " <> review())]) == %{}
    assert PullEvidence.parse([comment(1, "```\n#{review()}\n```")]) == %{}
  end

  test "unknown results and missing or mixed commits cannot be reported as passing" do
    for body <- [
          String.replace(validation(), @sha, ""),
          String.replace(validation(), "passou", "not run"),
          validation() <> "\n- `other`: passed em #{@other}"
        ] do
      refute PullEvidence.parse([comment(1, body)])["ci"]["result"] == "pass"
    end
  end

  test "new failure overrides a previous pass; unrelated later comment does not erase it" do
    failed = String.replace(validation(), "passou", "falhou")

    result =
      PullEvidence.parse([comment(1, validation()), comment(3, "thanks"), comment(2, failed)])

    assert result["ci"]["result"] == "fail"
    assert PullEvidence.parse([]) == %{}
  end

  test "comments from an unrelated contributor cannot supply quality reports" do
    outsider = Map.put(comment(1, validation()), "author_association", "NONE")
    assert PullEvidence.parse([outsider]) == %{}
  end

  test "a report never covers an unknown or different head" do
    report = PullEvidence.parse([comment(1, validation())])["ci"]
    assert PullEvidence.state(report, nil) == "unknown"
    assert PullEvidence.state(report, @other) == "stale"
  end

  test "a negated review and an incomplete new receipt cannot approve" do
    refute PullEvidence.parse([
             comment(1, String.replace(review(), "Approved head", "Not approved head"))
           ])["review"]["result"] == "approved"

    result =
      PullEvidence.parse([
        comment(1, validation()),
        comment(2, "### Validation\n- `make test`: running")
      ])

    assert result["ci"]["result"] == "unknown"
  end

  defp validation,
    do:
      "## Author self-review — not independent approval\n\n### Validação\n- `make test`: passou em #{@sha}\n- `node --test`: passed em #{@sha}"

  defp review,
    do:
      "## Independent agent review — final head\n\nReviewer: separate test-reviewer agent\nApproved head `#{@sha}`; no blockers."

  defp comment(id, body),
    do: %{
      "id" => id,
      "body" => body,
      "user" => %{"login" => "maintainer"},
      "author_association" => "OWNER",
      "html_url" => "https://github.com/example/app/pull/42#issuecomment-#{id}",
      "updated_at" => "2026-11-17T12:00:00Z"
    }
end
