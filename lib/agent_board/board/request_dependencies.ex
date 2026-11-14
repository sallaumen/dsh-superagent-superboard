defmodule AgentBoard.Board.RequestDependencies do
  @moduledoc "Prepares a request using the outcomes of the tasks it depends on."

  alias AgentBoard.Intake.IssueBody

  @doc """
  Names blockers whose issue numbers are known and holds runner requests for them.
  A failed blocker prevents creation; a key with no number yet adds no link.
  """
  @spec prepare(map(), %{optional(term()) => pos_integer() | :failed}) ::
          {:ok, map()} | {:error, :dependency_failed}
  def prepare(request, known_numbers) do
    blockers = request |> Map.get(:depends_on, []) |> Enum.flat_map(&List.wrap(known_numbers[&1]))

    if :failed in blockers do
      {:error, :dependency_failed}
    else
      body = IssueBody.with_dependencies(request.body, blockers, Map.get(request, :language))
      prepared = %{request | body: body}

      if blockers != [] and Map.get(request, :executor) in [nil, "dsh"],
        do: {:ok, Map.put(prepared, :held, true)},
        else: {:ok, prepared}
    end
  end
end
