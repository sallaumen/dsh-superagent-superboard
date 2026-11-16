defmodule AgentBoard.Lanes.Digest.Visit do
  @moduledoc "The reader's clock, previous visit and limit of the board's sync evidence."

  @enforce_keys [:now, :last_visit, :offset, :sync]
  defstruct @enforce_keys

  @type sync :: :live | :unconfirmed | {:through, DateTime.t()}
  @type t :: %__MODULE__{
          now: DateTime.t(),
          last_visit: DateTime.t() | nil,
          offset: integer(),
          sync: sync()
        }

  @doc "An explicit live state ignores a saved sync time. A frozen board can have no completed sync."
  @spec from_options(keyword()) :: t()
  def from_options(opts) do
    at = Keyword.get(opts, :frozen_at)
    frozen? = Keyword.get(opts, :frozen, not is_nil(at))

    %__MODULE__{
      now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0),
      last_visit: Keyword.get(opts, :last_visit),
      offset: Keyword.get(opts, :tz_offset, 0),
      sync: sync_state(frozen?, at)
    }
  end

  defp sync_state(false, _at), do: :live
  defp sync_state(true, nil), do: :unconfirmed
  defp sync_state(true, %DateTime{} = at), do: {:through, at}
end
