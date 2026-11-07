defmodule AgentBoard.WorkpadTest do
  @moduledoc "The workpad is read by section name; anything else is nil, never a guess."
  use ExUnit.Case, async: true

  alias AgentBoard.Workpad

  @full """
  This is by an automated agent, not a human.

  ## Relatório do agente

  ### Plano
  1. Ler o board.
  2. Abrir o [PR #28](https://github.com/fixture/repo/pull/28).

  ### Validação
  mix precommit: passou (326 testes) em 44653e8

  ### Pergunta
  Devo manter o boss na arena ou tirar

  ### Bloqueio
  """

  test "a full workpad is read by section" do
    assert %{
             plan: plan,
             validation: validation,
             question: "Devo manter o boss na arena ou tirar",
             blockage: nil,
             pull_requests: [28]
           } = Workpad.parse(@full)

    assert plan =~ "1. Ler o board."
    assert plan =~ "PR #28"

    assert validation == %{
             command: "mix precommit",
             passed?: true,
             sha: "44653e8",
             detail: "mix precommit: passou (326 testes) em 44653e8"
           }
  end

  test "a comment without the heading is not a workpad" do
    assert Workpad.parse("On it: changing the button label.") == nil
    assert Workpad.parse("### Pergunta\nIs this a question?") == nil
    assert Workpad.parse("# Relatório do agente\n### Pergunta\nNo: level one heading.") == nil
    assert Workpad.parse(nil) == nil
    assert Workpad.parse(%{}) == nil
  end

  test "the hidden runner marker is not part of the text" do
    body = "<!-- dsh-superagent:ticket -->\n## Relatório do agente\n### Pergunta\nQual API?"

    assert %{question: "Qual API?"} = Workpad.parse(body)
  end

  test "empty, placeholder and missing sections are nil" do
    body = """
    ## Relatório do agente

    ### Plano

    ### Validação
    —

    ### Pergunta
    (vazio)
    """

    assert Workpad.parse(body) == %{
             plan: nil,
             validation: nil,
             question: nil,
             blockage: nil,
             pull_requests: []
           }
  end

  test "a heading alone with no sections is still a workpad that says nothing" do
    assert %{plan: nil, question: nil, blockage: nil, validation: nil} =
             Workpad.parse("## Relatório do agente")
  end

  test "markdown inside a section stays in it; only ### splits" do
    body = """
    ## Relatório do agente

    ### Plano
    #### Etapa 1
    - item `com código`
    - ### not a heading inside a list item? no, a list item

    ```sh
    ### inside a fence is text too
    ```

    ### Bloqueio
    **Sem acesso** ao registry:
    - npm 403
    """

    assert %{plan: plan, blockage: blockage} = Workpad.parse(body)
    assert plan =~ "#### Etapa 1"
    assert plan =~ "com código"
    assert plan =~ "inside a fence"
    assert blockage =~ "**Sem acesso**"
    assert blockage =~ "npm 403"
  end

  test "section names tolerate case, English, colons and emphasis" do
    body = """
    ## RELATÓRIO DO AGENTE
    ### Plan:
    steps
    ### **Validation**
    mix precommit: passed (12 tests, 0 failures) at 9F1C2AB
    ### question
    Which one
    ### Blocker
    none
    """

    assert %{plan: "steps", question: "Which one", blockage: nil, validation: validation} =
             Workpad.parse(body)

    assert validation.passed? == true
    assert validation.sha == "9f1c2ab"
  end

  test "a question needs no question mark and a question mark elsewhere is not one" do
    body = """
    ## Relatório do agente
    ### Plano
    Should the plan ask? No: a question mark in the plan is not a question.
    ### Pergunta
    """

    assert %{question: nil} = Workpad.parse(body)
  end

  test "a failed gate, a gate without a result and a gate without a sha" do
    assert %{validation: %{passed?: false, sha: "a1b2c3d", command: "mix precommit"}} =
             Workpad.parse(
               "## Relatório do agente\n### Validação\nmix precommit: falhou (2 falhas) em a1b2c3d"
             )

    assert %{validation: %{passed?: false}} =
             Workpad.parse(
               "## Relatório do agente\n### Validação\n- mix precommit: 3 failures at a1b2c3d"
             )

    assert %{validation: %{passed?: nil, sha: nil, command: nil, detail: "rodando ainda"}} =
             Workpad.parse("## Relatório do agente\n### Validação\nrodando ainda")

    assert %{validation: %{passed?: true, sha: nil}} =
             Workpad.parse("## Relatório do agente\n### Validação\nmix precommit: ok")
  end

  test "the precommit line wins over other gates and whitespace collapses" do
    body = """
    ## Relatório do agente
    ### Validação
    - mix format: ok
    - `mix precommit`:   passou   (326 testes)
      em 44653e8
    """

    assert %{validation: %{command: "mix precommit", passed?: true, sha: "44653e8"}} =
             Workpad.parse(body)
  end

  test "a word of hex letters without a digit is not a sha" do
    assert %{validation: %{sha: nil}} =
             Workpad.parse("## Relatório do agente\n### Validação\nmix precommit: passou, decade")
  end

  test "the PR numbers come from anywhere in the comment, once each" do
    body = """
    ## Relatório do agente
    ### Plano
    PR #28 e https://github.com/fixture/repo/pull/30
    ### Validação
    mix precommit: passou em 44653e8 (PR #28)
    """

    assert %{pull_requests: [28, 30]} = Workpad.parse(body)
  end
end
