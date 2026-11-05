defmodule AgentBoard.AI.Cache do
  @moduledoc """
  An identical registered call, served from a stored answer instead of paying
  again.

  The key is the call name, the provider, the model and a hash of the inputs:
  the same request to the same engine cannot answer differently, so the row
  that already paid for it is the right answer. Only a `complete` answer is
  reusable -- a partial one is a truncated answer, and serving it would turn
  one failure into many.
  """

  import Ecto.Query

  alias AgentBoard.AI.Call
  alias AgentBoard.Repo

  @default_ttl_seconds 3600

  @doc "The fingerprint of a call."
  @spec key(atom(), atom(), String.t() | nil, map()) :: String.t()
  def key(name, provider, model, inputs) do
    :crypto.hash(:sha256, [
      to_string(name),
      to_string(provider),
      to_string(model),
      Jason.encode!(inputs)
    ])
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
