defmodule AgentBoard.AttributionTest do
  @moduledoc "Which task a session or a PR worked for: the rules of docs/research/alfred.md, 3.4."
  use ExUnit.Case, async: true

  alias AgentBoard.Attribution

  @portal %{id: 1, owner: "example", name: "o_portal"}
  @arena %{id: 2, owner: "example", name: "atlas-relay"}

  # Task 10 is issue #412 in o_portal; task 20 is issue #7 in atlas-relay.
  @tasks [
    %{id: 10, repository_id: 1, number: 412},
    %{id: 20, repository_id: 2, number: 7}
  ]

  defp index(pulls), do: Attribution.index([@portal, @arena], pulls, @tasks)

  defp pull(attrs) do
    Map.merge(%{repository_id: 1, number: 455, head_ref: nil, closes_issues: []}, attrs)
  end

  describe "closing_numbers/3" do
    test "reads GitHub's closing keywords, each with its own reference" do
      body = """
      Closes #412. fixes #3, Resolved: #9
      Closes #1, #2
      """

      assert Attribution.closing_numbers(body, "example", "o_portal") == [412, 3, 9, 1]
    end

    test "keeps a reference to the same repository and drops another repository's" do
      body = """
      Closes example/o_portal#5
      Fixes https://github.com/example/o_portal/issues/6
      Closes example/atlas-relay#7
      Fixes https://github.com/other/o_portal/issues/8
      """

      assert Attribution.closing_numbers(body, "example", "o_portal") == [5, 6]
    end

    test "a body without a closing keyword closes nothing" do
      assert Attribution.closing_numbers("See #412 and PR #3", "example", "o_portal") == []
      assert Attribution.closing_numbers("encloses #4 prefixes #5", "example", "o_portal") == []
      assert Attribution.closing_numbers(nil, "example", "o_portal") == []
    end

    test "a repeated reference counts once, in the order first named" do
      assert Attribution.closing_numbers("Closes #2\nCloses #1\nfixes #2", "a", "b") == [2, 1]
    end
  end

  describe "task_for_pull/2" do
    test "a PR that closes a task's issue belongs to that task" do
      assert Attribution.task_for_pull(pull(%{closes_issues: [412]}), index([])) == 10
    end

    test "a PR without Closes #n has no task" do
      assert Attribution.task_for_pull(pull(%{closes_issues: []}), index([])) == nil
    end

    test "an issue number from another repository is not this PR's task" do
      assert Attribution.task_for_pull(pull(%{closes_issues: [7]}), index([])) == nil
    end

    test "the first closed issue that is a task wins" do
      assert Attribution.task_for_pull(pull(%{closes_issues: [999, 412]}), index([])) == 10
    end
  end

  describe "for_session/2" do
    test "a dispatched session is exact, whatever else it carries" do
      session = %{task_id: 20, pr_links: [%{repository: "example/o_portal", number: 455}]}
      pulls = [pull(%{closes_issues: [412]})]

      assert Attribution.for_session(session, index(pulls)) == {:task, 20, :exact}
    end

    test "a Claude Code pr-link to a PR that closes a task attributes to it" do
      session = %{
        pr_links: [%{repository: "example/o_portal", number: 455}],
        git_branch: "claude/other",
        cwd: "/Users/example/projects/o_portal/.claude/worktrees/ui-fix"
      }

      pulls = [pull(%{head_ref: "claude/ui-fix", closes_issues: [412]})]

      assert Attribution.for_session(session, index(pulls)) == {:task, 10, :pr_link}
    end

    test "the session's branch is the head of a PR that closes a task" do
      session = %{
        git_branch: "claude/ui-fix",
        cwd: "/Users/example/projects/o_portal/.claude/worktrees/ui-fix"
      }

      pulls = [pull(%{head_ref: "claude/ui-fix", closes_issues: [412]})]

      assert Attribution.for_session(session, index(pulls)) == {:task, 10, :branch}
    end

    test "the Codex remote names the repository for the branch rule" do
      session = %{git_branch: "fix/x", origin_url: "git@github.com:example/atlas-relay.git"}
      pulls = [pull(%{repository_id: 2, number: 30, head_ref: "fix/x", closes_issues: [7]})]

      assert Attribution.for_session(session, index(pulls)) == {:task, 20, :branch}
    end

    test "the same branch name in another repository is not the PR's" do
      session = %{git_branch: "claude/ui-fix", cwd: "/Users/example/projects/atlas-relay"}
      pulls = [pull(%{head_ref: "claude/ui-fix", closes_issues: [412]})]

      assert Attribution.for_session(session, index(pulls)) == {:repository, 2}
    end

    test "a session whose PR has no Closes #n is direct work in the repository" do
      session = %{
        pr_links: [%{repository: "example/o_portal", number: 455}],
        git_branch: "claude/ui-fix"
      }

      pulls = [pull(%{head_ref: "claude/ui-fix", closes_issues: []})]

      assert Attribution.for_session(session, index(pulls)) == {:repository, 1}
    end

    test "a detached HEAD is not a branch" do
      session = %{git_branch: "HEAD", cwd: "/Users/example/projects/o_portal"}
      pulls = [pull(%{head_ref: "HEAD", closes_issues: [412]})]

      assert Attribution.for_session(session, index(pulls)) == {:repository, 1}
    end

    test "a repository the board does not track is outside, by its folder" do
      session = %{
        git_branch: "main",
        cwd: "/Users/example/projects/catalog-page/.claude/worktrees/hero"
      }

      assert Attribution.for_session(session, index([])) == {:outside, "catalog-page"}
    end

    test "a session with no metadata is unknown, never a guess" do
      assert Attribution.for_session(%{}, index([])) == :unknown
    end

    test "a folder name two board repositories share does not pick one" do
      twin = %{id: 3, owner: "other", name: "o_portal"}
      index = Attribution.index([@portal, twin], [], @tasks)

      assert Attribution.for_session(%{cwd: "/x/o_portal"}, index) == {:outside, "o_portal"}
    end
  end
end
