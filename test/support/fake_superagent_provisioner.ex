defmodule AgentBoard.Superagents.FakeProvisioner do
  @moduledoc "Test provisioner: records the call and answers the row's own paths, or `attrs.fail`."
  @behaviour AgentBoard.Superagents.Provisioner

  def provision(_superagent, _source, %{fail: reason}), do: {:error, reason}

  def provision(superagent, source, attrs) do
    Process.put({__MODULE__, :last}, {superagent, source, attrs})
    {:ok, %{profile: superagent.profile, port: superagent.port, state_dir: superagent.state_dir}}
  end
end
