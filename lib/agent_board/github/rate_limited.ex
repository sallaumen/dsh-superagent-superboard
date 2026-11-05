defmodule AgentBoard.GitHub.RateLimited do
  @moduledoc """
  GitHub refused the request because the token spent its quota.

  It is an exception, not an error tuple, because every GitHub call already
  raises on a bad status -- and it carries the wait GitHub asked for, so the
  caller can snooze instead of hammering the API again.
  """

  defexception [:retry_after]

  @impl Exception
  def message(%__MODULE__{retry_after: seconds}) do
    "GitHub rate limited: retry after #{seconds}s"
  end
end
