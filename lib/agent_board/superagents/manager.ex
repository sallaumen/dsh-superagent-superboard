defmodule AgentBoard.Superagents.Manager do
  @moduledoc """
  The boundary between the board and the external `dsh-superagent` manager.
  The board never assumes a process layout; an adapter answers status and
  performs start/stop/pause/scale and edits who may use the agent. The default is `DshManager`; tests use the
  fake in `test/support`.
  """

  alias AgentBoard.Superagents.Superagent

  @callback status(Superagent.t()) :: {:ok, map()} | {:error, term()}
  @callback start(Superagent.t()) :: :ok | {:error, term()}
  @callback stop(Superagent.t()) :: :ok | {:error, term()}
  @callback pause(Superagent.t(), boolean()) :: :ok | {:error, term()}
  @callback scale(Superagent.t(), pos_integer()) :: :ok | {:error, term()}
  @callback access(Superagent.t()) ::
              {:ok, %{allowed: [%{login: String.t(), name: String.t() | nil}]}} | {:error, term()}
  @callback allow(Superagent.t(), String.t()) :: :ok | {:error, term()}
  @callback disallow(Superagent.t(), String.t()) :: :ok | {:error, term()}
  @callback requeue(Superagent.t(), String.t()) :: {:ok, boolean()} | {:error, term()}

  @doc "The configured adapter."
  def impl,
    do: Application.get_env(:agent_board, :superagent_manager, AgentBoard.Superagents.DshManager)
end
