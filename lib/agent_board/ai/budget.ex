defmodule AgentBoard.AI.Budget do
  @moduledoc """
  A daily token cap, checked before a call.

  The panel is a tool, not a service: an unbounded loop of refines would be a
  silent bill. When the cap is reached a call answers `:budget_exhausted`
  before reaching the network -- and the refusal is not a crash.
  """

  import Ecto.Query

  alias AgentBoard.AI.Call
  alias AgentBoard.Repo

  @default_tokens 5_000_000

  @spec check(atom()) :: :ok | {:error, :budget_exhausted}
  def check(_tier) do
    if tokens_today() >= cap(), do: {:error, :budget_exhausted}, else: :ok
  end

  @spec tokens_today() :: non_neg_integer()
  def tokens_today do
    start =
      DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00.000000], "Etc/UTC")

    Repo.one(
      from c in Call,
        where: c.inserted_at >= ^start,
        select: %{input: sum(c.input_tokens), output: sum(c.output_tokens)}
    )
    |> case do
      %{input: nil} -> 0
      %{input: input, output: output} -> input + (output || 0)
    end
  end

  @spec cap() :: non_neg_integer()
  def cap, do: Application.get_env(:agent_board, :ai_daily_tokens, @default_tokens)
end
