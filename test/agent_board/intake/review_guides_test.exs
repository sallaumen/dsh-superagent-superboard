defmodule AgentBoard.Intake.ReviewGuidesTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Intake
  alias AgentBoard.Intake.{IssueBody, ReviewGuides}

  @tag :tmp_dir
  test "only reviewed, verified guides reach the issue; host paths and file contents stay local",
       %{tmp_dir: root} do
    File.mkdir_p!(Path.join(root, "motion-designer"))
    File.write!(Path.join(root, "motion-designer/SKILL.md"), "private skill instructions")
    path = ".agents/skills/swarm-art/SKILL.md"

    tree = [
      %{"path" => path, "type" => "blob"},
      %{"path" => "docs/MOTION_REVIEW.md", "type" => "tree"}
    ]

    catalog =
      ReviewGuides.available(
        %{url: "https://github.com/fixture/game", paths: ReviewGuides.from_tree(tree)},
        [root]
      )

    draft = %{
      title: "Impact",
      body: "Heavy shell",
      acceptance: ["Local to victim"],
      verification: "Compare seed 7",
      review_method: "motion",
      project_guide: path
    }

    task = ReviewGuides.attach(draft, catalog)
    render = &IssueBody.render(&1, %{"language" => "en"})
    assert render.(task) =~ "https://github.com/fixture/game/blob/HEAD/#{path}"
    refute render.(task) =~ "motion-designer"

    edits = %{
      "0" => %{
        "title" => "Impact",
        "body" => "Heavy shell",
        "acceptance" => "Only the target",
        "verification" => "Compare with the numbers off",
        "guides" => ["motion-designer", "/secret", "https://bad"]
      }
    }

    [edited] = Intake.edit_tasks([task], edits)
    body = render.(edited)
    assert body =~ "Compare with the numbers off"
    assert body =~ "`motion-designer` (if available on the executor)"

    for absent <- [
          root,
          "private skill instructions",
          "/secret",
          "https://bad",
          path,
          "Compare seed 7"
        ],
        do: refute(body =~ absent)

    other =
      ReviewGuides.attach(
        %{draft | project_guide: "https://bad", review_method: "inspection"},
        catalog
      )

    refute render.(other) =~ "Suggested guides"
  end

  test "search is bounded and a directory, symlink or malformed name is not a skill" do
    blob = fn path -> %{"type" => "blob", "path" => path} end
    skills = for i <- 1..60, do: blob.(".agents/skills/guide-#{i}/SKILL.md")
    guide = "docs/MOTION_REVIEW.md"
    link = Map.put(blob.(guide), "mode", "120000")

    known =
      ReviewGuides.from_tree([
        link,
        blob.(".agents/skills/escape/SKILL.md\n"),
        blob.("a/.agents/skills/off/SKILL.md") | skills
      ])

    assert length(known) == 32
    refute guide in known
    assert known == Enum.sort(known)
    assert Enum.all?(known, &String.starts_with?(&1, ".agents/skills/guide-"))
  end

  test "a project can supply a skill on another board without any machine catalog" do
    path = ".agents/skills/ui-review/SKILL.md"
    project = %{url: "https://github.com/fixture/game", paths: [path]}

    assert [%{scope: :project, id: ^path}] =
             ReviewGuides.available(project, []).methods["interaction"]

    assert [] == ReviewGuides.available(nil, []).methods["motion"]
  end
end
