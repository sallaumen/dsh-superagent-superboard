defmodule AgentBoard.Voice.Activity do
  @moduledoc """
  What the voice pipeline is doing, as it happens: one event per stage of a
  turn (heard, transcribed, thinking, answered, spoken), every retry and
  every failure, from the server and from the browser.

  Each event is three things at once:

    * a structured log line (`voice stage=tts status=retry attempt=2 ...`)
      with the stage, status and turn in the logger metadata, at `info`,
      `warning` (a retry) or `error`;
    * a `{:voice_activity, event}` broadcast on the `"voice:activity"`
      PubSub topic, which the board shows live;
    * an entry in a small in-memory ring (`recent/0`), so a page that opens
      later still sees the last events. A restart empties it: the durable
      records stay where they were (`voice_turns`, `ai_calls`).

  An event never carries a secret or a whole utterance: the detail is a
  short, human sentence and the numbers that explain it.
  """
  use GenServer

  require Logger

  @topic "voice:activity"
  @keep 60
  @statuses [:start, :ok, :retry, :error, :info]

  @type event :: %{
          id: pos_integer(),
          at: DateTime.t(),
          stage: atom(),
          status: atom(),
          detail: String.t(),
          ms: non_neg_integer() | nil,
          attempt: pos_integer() | nil,
          turn: term()
        }

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "The PubSub topic of the live feed."
  def topic, do: @topic

  @doc "Subscribes the caller to the live feed."
  def subscribe, do: Phoenix.PubSub.subscribe(AgentBoard.PubSub, @topic)

  @doc """
  Records an event. `stage` names the step (`:turn`, `:transcribe`,
  `:model`, `:action`, `:tts`, `:browser`, `:ui`...), `status` is one of
  `#{inspect(@statuses)}`. Options: `:ms`, `:attempt`, `:turn`, `:reason`
  (logged, also appended to the detail in words).
  """
  @spec record(atom(), atom(), String.t(), keyword()) :: :ok
  def record(stage, status, detail, opts \\ []) when status in @statuses do
    event = %{
      id: System.unique_integer([:positive, :monotonic]),
      at: DateTime.utc_now(),
      stage: stage,
      status: status,
      detail: detail(detail, opts[:reason]),
      ms: opts[:ms],
      attempt: opts[:attempt],
      turn: opts[:turn]
    }

    log(event, opts[:reason])
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:record, event})
    Phoenix.PubSub.broadcast(AgentBoard.PubSub, @topic, {:voice_activity, event})
    :ok
  end

  @doc "The last events, newest first."
  @spec recent() :: [event()]
  def recent do
    if Process.whereis(__MODULE__), do: GenServer.call(__MODULE__, :recent), else: []
  end

  @doc "Forgets the recent events (tests)."
  def clear,
    do: if(Process.whereis(__MODULE__), do: GenServer.call(__MODULE__, :clear), else: :ok)

  @doc "A failure reason in words, for the detail and the log."
  @spec reason(term()) :: String.t()
  def reason(:not_configured), do: "sem chave configurada"
  def reason(:auth_expired), do: "chave recusada (401)"
  def reason(:usage_limit), do: "limite de uso (429)"
  def reason(:budget_exhausted), do: "orçamento de IA esgotado"
  def reason(:timeout), do: "tempo esgotado"
  def reason(:no_provider), do: "nenhum provedor de IA respondeu"
  def reason({:http, status}), do: "HTTP #{status}"
  def reason(%{__exception__: true} = e), do: Exception.message(e)
  def reason(other) when is_atom(other), do: Atom.to_string(other)
  def reason(other) when is_binary(other), do: other
  def reason(other), do: inspect(other, limit: 5, printable_limit: 120)

  @impl true
  def init(:ok), do: {:ok, []}

  @impl true
  def handle_cast({:record, event}, events), do: {:noreply, Enum.take([event | events], @keep)}

  @impl true
  def handle_call(:recent, _from, events), do: {:reply, events, events}
  def handle_call(:clear, _from, _events), do: {:reply, :ok, []}

  defp detail(detail, nil), do: detail
  defp detail(detail, reason), do: "#{detail} (#{reason(reason)})"

  defp log(event, _reason) do
    fields =
      [
        stage: event.stage,
        status: event.status,
        turn: event.turn,
        attempt: event.attempt,
        ms: event.ms
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    line =
      "voice " <>
        Enum.map_join(fields, " ", fn {k, v} -> "#{k}=#{format(v)}" end) <>
        " — " <> event.detail

    Logger.log(level(event.status), line)
  end

  defp format(v) when is_binary(v), do: if(String.contains?(v, " "), do: inspect(v), else: v)
  defp format(v), do: to_string(v)

  defp level(:error), do: :error
  defp level(:retry), do: :warning
  defp level(_status), do: :info
end
