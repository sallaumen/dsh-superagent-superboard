defmodule AgentBoard.GitHub.HTTPError do
  @moduledoc """
  GitHub answered a 4xx/5xx that is not a rate limit.

  The status is a field, not a prefix to parse out of the message: the sync
  decides "Issues disabled, keep syncing pulls" on 404/410 and the panel names
  a refused token on 401/403, and both match on `status`.
  """

  defexception [:status, :body]

  @impl Exception
  def message(%__MODULE__{status: status, body: body}) do
    "GitHub HTTP #{status}: #{inspect(body)}"
  end
end
