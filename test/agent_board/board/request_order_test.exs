defmodule AgentBoard.Board.RequestOrderTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.RequestOrder

  test "a free request keeps its priority and receipts keep their input positions" do
    last = %{key: "last", depends_on: ["middle"]}
    free = %{key: "free"}
    middle = %{key: "middle", depends_on: ["first"]}
    first = %{key: "first"}

    assert RequestOrder.for_creation([last, free, middle, first]) ==
             [{free, 1}, {first, 3}, {middle, 2}, {last, 0}]
  end

  test "only a cycle member can open before its blocker" do
    outside = %{key: "outside", depends_on: ["b"]}
    a = %{key: "a", depends_on: ["b"]}
    b = %{key: "b", depends_on: ["a"]}

    assert RequestOrder.for_creation([outside, a, b]) == [{a, 1}, {b, 2}, {outside, 0}]
  end
end
