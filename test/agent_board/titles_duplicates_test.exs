defmodule AgentBoard.TitlesDuplicatesTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Titles

  test "the highest score wins, including the threshold; equal scores keep history order" do
    partial = %{number: 7, title: "Revisar ação da fila hoje"}
    exact = %{number: 9, title: "REVISAR: ACAO DA FILA"}
    tie = %{number: 12, title: "Fila da ação: revisar"}
    title = "revisar ação da fila"

    unrelated = %{number: 20, title: "Build release"}

    assert Titles.duplicates([title, title, nil, "!", "editar fila", "BUILD release"], [
             partial,
             exact,
             tie,
             unrelated
           ]) ==
             %{title => exact, "BUILD release" => unrelated}

    assert Titles.duplicates([title], [partial]) == %{title => partial}
    assert Titles.duplicate(title, [tie, exact]) == tie
    assert Titles.duplicates([title], []) == %{}
  end
end
