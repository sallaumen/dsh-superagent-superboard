defmodule AgentBoardWeb.FailureText do
  @moduledoc """
  What the panel says when a call to another service failed.

  One sentence for a person: what happened, in the interface's language. A
  reason the board does not know is logged and said generically; an Elixir term
  never reaches the screen.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.GitHub.{HTTPError, RateLimited}

  require Logger

  @never_reached [:nxdomain, :econnrefused, :ehostunreach, :enetunreach]

  @spec text(term()) :: String.t()
  def text({:error, reason}), do: text(reason)
  def text(:not_configured), do: gettext("The key for this service is not configured.")
  def text(:auth_expired), do: gettext("The service refused the key.")
  def text(:usage_limit), do: gettext("The service's usage limit was reached.")
  def text(:quota_exceeded), do: gettext("The service's credits are spent.")
  def text(:budget_exhausted), do: gettext("The board's AI budget is exhausted.")
  def text(:timeout), do: gettext("The service did not respond in time.")
  def text(:unreachable), do: gettext("The service did not respond.")

  # Preparing a project (`AgentBoard.Superagents`): the dsh profile and the form.
  def text({:profile_port_missing, name}),
    do: gettext("The dsh profile %{name} has no port yet; open it once in dsh.", name: name)

  def text(:profile_missing), do: gettext("That dsh profile is not on this machine.")
  def text(:source_required), do: gettext("Choose the dsh profile the project starts from.")

  def text(:invalid_workers),
    do: gettext("The number of workers must be from %{min} to %{max}.", range())

  def text(%Ecto.Changeset{}), do: gettext("Some values were not accepted; check the form.")

  def text({:http, status}) when is_integer(status),
    do: gettext("The service answered with an error (HTTP %{status}).", status: status)

  def text(%RateLimited{retry_after: seconds}) do
    gettext("GitHub is limiting calls; try again in %{minutes} min.",
      minutes: max(div(seconds + 59, 60), 1)
    )
  end

  def text(%Req.TransportError{reason: reason}) when reason in @never_reached,
    do: gettext("Could not reach the service; check the network.")

  def text(%Req.TransportError{}), do: gettext("The connection dropped before an answer.")

  def text(%HTTPError{status: status}) when status in [401, 403],
    do: gettext("GitHub refused the board's token (HTTP %{status}).", status: status)

  def text(%HTTPError{status: status}),
    do: gettext("GitHub answered with an error (HTTP %{status}).", status: status)

  def text(%{__exception__: true} = exception), do: unexpected(exception)
  def text(reason) when is_binary(reason), do: String.slice(reason, 0, 200)
  def text(reason), do: unexpected(reason)

  defp range do
    first..last//_step = AgentBoard.Orchestrator.worker_range()
    [min: first, max: last]
  end

  defp unexpected(reason) do
    Logger.warning("panel failure: #{inspect(reason)}")
    gettext("Something unexpected went wrong; the detail is in the log.")
  end
end
