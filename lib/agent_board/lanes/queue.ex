defmodule AgentBoard.Lanes.Queue do
  @moduledoc "Rules for the queue, applied to the rows the board observed."

  @doc "A task names what it unblocks before the task it was split from."
  @spec relationship(integer() | nil, integer() | nil) ::
          {:unblocks | :split_from, integer()} | nil
  def relationship(blocked_number, _origin) when is_integer(blocked_number),
    do: {:unblocks, blocked_number}

  def relationship(nil, origin) when is_integer(origin), do: {:split_from, origin}
  def relationship(_blocked_number, _origin), do: nil
end
