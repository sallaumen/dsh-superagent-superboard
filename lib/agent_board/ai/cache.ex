defmodule AgentBoard.AI.Cache do
  @moduledoc """
  An identical registered call, served from a stored answer instead of paying
  again.

  The key includes the registered prompt and response contract. A change to
  either cannot reuse an answer paid for under the old contract. Only a `complete` answer is
  reusable -- a partial one is a truncated answer, and serving it would turn
  one failure into many.
  """

  import Ecto.Query

  alias AgentBoard.AI.Call
  alias AgentBoard.Repo

  @default_ttl_seconds 3600

  @doc "The fingerprint of a call."
  @spec key(atom(), atom(), String.t() | nil, map(), map()) :: String.t()
  def key(name, provider, model, inputs, spec) do
    :crypto.hash(
      :sha256,
      Jason.encode!(%{
        name: name,
        provider: provider,
        model: model,
        inputs: inputs,
        system: spec.system,
        json_schema: spec.json_schema,
        tier: spec.tier,
        output_cap: spec.output_cap
      })
    )
    |> Base.encode16(case: :lower)
  end

  @doc "A stored complete answer for this key within the ttl, if there is one."
  @spec get(String.t()) :: {:ok, map()} | :miss
  def get(key) do
    since = DateTime.add(DateTime.utc_now(), -ttl(), :second)

    case Repo.one(
           from c in Call,
             where:
               c.input_hash == ^key and c.status == "ok" and
                 c.parse_state == "complete" and c.inserted_at >= ^since,
             order_by: [desc: c.inserted_at, desc: c.id],
             limit: 1
         ) do
      %Call{json: %{} = json} -> {:ok, json}
      _ -> :miss
    end
  end

  @spec ttl() :: pos_integer()
  def ttl, do: Application.get_env(:agent_board, :ai_cache_ttl_seconds, @default_ttl_seconds)
end
