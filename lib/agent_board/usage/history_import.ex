defmodule AgentBoard.Usage.HistoryImport do
  @moduledoc "Owner permission for machine-wide reads of local executor sessions."
  alias AgentBoard.Settings

  @doc "Whether the owner has enabled reading executor history from this machine."
  @spec enabled?() :: boolean()
  def enabled?, do: Settings.get("import_executor_history") == "true"
end
