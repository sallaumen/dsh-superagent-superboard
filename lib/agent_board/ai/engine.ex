defmodule AgentBoard.AI.Engine do
  @moduledoc """
  The port to a language model. One adapter per engine, a stub in tests.

  `run/1` answers `{:ok, Result.t()}` or `{:error, reason}`; a failure is a
  reason, never a fabricated answer. `status/0` reads whether the engine is
  configured without spending a token.
  """

  alias AgentBoard.AI.{Request, Result}

  @type reason ::
          :not_configured
          | :auth_expired
          | :usage_limit
          | :malformed_output
          | {:http, integer()}
          | term()

  @type status :: :logged_in | :not_configured | :unavailable | :rehearsal

  @callback run(Request.t()) :: {:ok, Result.t()} | {:error, reason()}
  @callback status() :: status()

  @optional_callbacks status: 0
end
