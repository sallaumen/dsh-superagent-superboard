defmodule AgentBoard.AgentFailure do
  @moduledoc """
  What a `failed` report from the agent means, read from its summary: a
  passing failure the system can retry on its own, or one a person has to
  look at.

  Transient means the request never reached a working peer: the model's
  transport, a name that did not resolve, a connection refused or reset, a
  timeout, the provider's rate limit or a 5xx. Everything else, including an
  unknown text, needs a person: a guess never earns an automatic retry.

  Pure: no network, no database. `AgentBoard.AutoRetry` decides what to do
  with the result and stores it in Portuguese with `describe/1`; the screen
  says it in the viewer's language with `headline/1`.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  @type cause ::
          :model_transport
          | :dns
          | :connection
          | :timeout
          | :rate_limit
          | :provider_unavailable
          | :hung
          | :unknown
  @type stage :: :model | :prepare | :other
  @type t :: %{transient: boolean(), cause: cause(), stage: stage(), summary: String.t()}

  # The order matters: the first cause that matches names the failure. A
  # command the runner aborted at its own deadline (the prepare waits ten
  # minutes, typically on a credential prompt) is not the network: a person.
  @causes [
    hung: ~r/aborted due to timeout|timeouterror/i,
    dns:
      ~r/could not resolve host|enotfound|eai_again|getaddrinfo|name or service not known|nodename nor servname/i,
    connection:
      ~r/econnrefused|connection refused|econnreset|connection reset|socket hang up|fetch failed|failed to connect|network is unreachable|epipe|und_err|network error/i,
    timeout: ~r/etimedout|timed out|timeout/i,
    rate_limit: ~r/rate.?limit|too many requests|\b429\b|overloaded/i,
    provider_unavailable:
      ~r/\b50[0234]\b|service unavailable|bad gateway|gateway timeout|internal server error/i,
    model_transport: ~r/transport failed|transport error/i
  ]

  @doc "The failure a report summary describes."
  @spec classify(String.t() | nil) :: t()
  def classify(summary) when is_binary(summary) do
    cause = cause(summary)

    %{
      transient: cause not in [:unknown, :hung],
      cause: cause,
      stage: stage(summary),
      summary: summary
    }
  end

  def classify(_summary), do: classify("")

  defp cause(summary) do
    Enum.find_value(@causes, :unknown, fn {cause, pattern} ->
      if summary =~ pattern, do: cause
    end)
  end

  defp stage(summary) do
    cond do
      summary =~ ~r/prepare command failed/i -> :prepare
      summary =~ ~r/\bLlmError\b|deepseek|anthropic|openai|\bmodel\b/i -> :model
      true -> :other
    end
  end

  @doc "One short sentence for what went wrong, in the board's voice."
  @spec describe(t()) :: String.t()
  def describe(%{transient: true, stage: :model, cause: :rate_limit}),
    do: "O provedor do modelo limitou as requisições"

  def describe(%{transient: true, stage: :model, cause: :provider_unavailable}),
    do: "O provedor do modelo está fora do ar"

  def describe(%{transient: true, stage: :model}), do: "Falha de rede ao chamar o modelo"

  def describe(%{transient: true, stage: :prepare, cause: :dns}),
    do: "Sem rede ao preparar o worktree: o GitHub não resolveu"

  def describe(%{transient: true, stage: :prepare}),
    do: "Sem rede ao preparar o worktree"

  def describe(%{transient: true, cause: :rate_limit}), do: "Limite de requisições atingido"
  def describe(%{transient: true}), do: "Falha de rede"

  def describe(%{cause: :hung, stage: :prepare}),
    do: "O preparo do worktree passou do tempo limite"

  def describe(%{stage: :prepare}), do: "O preparo do worktree falhou"
  def describe(%{stage: :model}), do: "O modelo devolveu um erro"
  def describe(_failure), do: "O agente relatou uma falha"

  @doc """
  The sentence of `describe/1` in the viewer's language, for the screen.
  `describe/1` stays Portuguese: its text is stored with the retry.
  """
  @spec headline(t()) :: String.t()
  def headline(%{transient: true, stage: :model, cause: :rate_limit}),
    do: gettext("The model provider rate-limited the requests")

  def headline(%{transient: true, stage: :model, cause: :provider_unavailable}),
    do: gettext("The model provider is down")

  def headline(%{transient: true, stage: :model}),
    do: gettext("Network failure calling the model")

  def headline(%{transient: true, stage: :prepare, cause: :dns}),
    do: gettext("No network preparing the worktree: GitHub did not resolve")

  def headline(%{transient: true, stage: :prepare}),
    do: gettext("No network preparing the worktree")

  def headline(%{transient: true, cause: :rate_limit}), do: gettext("Request limit reached")
  def headline(%{transient: true}), do: gettext("Network failure")

  def headline(%{cause: :hung, stage: :prepare}),
    do: gettext("Preparing the worktree timed out")

  def headline(%{stage: :prepare}), do: gettext("Preparing the worktree failed")
  def headline(%{stage: :model}), do: gettext("The model returned an error")
  def headline(_failure), do: gettext("The agent reported a failure")
end
