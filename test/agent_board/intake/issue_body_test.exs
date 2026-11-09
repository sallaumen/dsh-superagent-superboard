defmodule AgentBoard.Intake.IssueBodyTest do
  @moduledoc "An issue from a split carries what the request decided, not only its own slice."
  use ExUnit.Case, async: true

  alias AgentBoard.Intake.IssueBody

  @task %{body: "Trocar o menu.", acceptance: ["Menu novo", "Sem rota quebrada"]}

  @spec_pt %{
    "goal" => "Organizar a navegação",
    "constraints" => ["Sem reescrever o contexto"],
    "non_goals" => ["Trocar a identidade visual"],
    "assumptions" => ["Há um layout compartilhado"],
    "blocking_questions" => [],
    "open_questions" => ["Quais são as telas duplicadas?"],
    "risks" => ["Links salvos podem quebrar"],
    "language" => "pt"
  }

  test "the issue carries the task, its acceptance and the request's decisions" do
    body = IssueBody.render(@task, @spec_pt)

    assert body =~ "Trocar o menu."
    assert body =~ "## Critérios de aceite\n- Menu novo\n- Sem rota quebrada"
    assert body =~ "**Objetivo:** Organizar a navegação"
    assert body =~ "### Restrições\n- Sem reescrever o contexto"
    assert body =~ "### Fora do escopo\n- Trocar a identidade visual"
    assert body =~ "### Suposições\n- Há um layout compartilhado"
    assert body =~ "### Perguntas em aberto\n- Quais são as telas duplicadas?"
  end

  test "the headings follow the request's language" do
    body = IssueBody.render(@task, %{@spec_pt | "language" => "en"})

    assert body =~ "## Acceptance criteria"
    assert body =~ "### Constraints"
    refute body =~ "Critérios de aceite"
  end

  test "a section with nothing to say is left out" do
    body = IssueBody.render(@task, %{"goal" => "Organizar", "constraints" => []})

    assert body =~ "**Objetivo:** Organizar"
    refute body =~ "### Restrições"
    refute body =~ "### Suposições"
  end

  test "a request without a specification still opens a whole task" do
    body = IssueBody.render(@task, %{})

    assert body =~ "## Critérios de aceite"
    refute body =~ "## Contexto do pedido"
  end

  test "the dependencies open the issue, as links GitHub resolves" do
    body = IssueBody.with_dependencies("Trocar o menu.", [12, 13], "pt")

    assert String.starts_with?(body, "**Depende de:** #12, #13")
    assert String.ends_with?(body, "Trocar o menu.")
  end

  test "no dependency leaves the body as it was" do
    assert IssueBody.with_dependencies("Trocar o menu.", [], "pt") == "Trocar o menu."
  end
end
