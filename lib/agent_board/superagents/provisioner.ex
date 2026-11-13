defmodule AgentBoard.Superagents.Provisioner do
  @moduledoc """
  Creates the external side of a new superagent (profile, port, state and
  setup) after the board row is reserved. The real implementation is
  `DshProvisioner`; tests inject a fake.
  """

  alias AgentBoard.Superagents.Superagent

  @callback provision(Superagent.t(), Superagent.t() | :first | nil, map()) ::
              {:ok, map()} | {:error, term()}

  @doc "Whether this machine can take its first agent, read before the owner confirms."
  @callback first_ready() :: :ok | {:error, term()}

  def impl,
    do:
      Application.get_env(
        :agent_board,
        :superagent_provisioner,
        AgentBoard.Superagents.DshProvisioner
      )
end
