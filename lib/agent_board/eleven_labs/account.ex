defmodule AgentBoard.ElevenLabs.Account do
  @moduledoc """
  The ElevenLabs account as the board knows it: the plan's characters used
  and left this period, read every 15 minutes (`ElevenLabs.subscription/0`,
  which spends nothing), and whether the paid voice is spent.

  Spent means the plan has no characters left before it renews, or a speech
  was just refused with `quota_exceeded`. The latter holds for an hour: a long
  text can be refused while a short one would still pass, so the paid voice
  is tried again after it. While spent, `VoiceSpeech` sends every utterance
  to the computer voice and the Attention bell says so. Readers take the
  state from `:persistent_term`; only this process and `mark_spent/1` write it.
  """
  use GenServer

  alias AgentBoard.ElevenLabs
  alias AgentBoard.Voice.Activity

  @key {__MODULE__, :state}
  @every :timer.minutes(15)
  @refused_for 3600

  @type t :: %{
          subscription:
            %{
              used: integer(),
              limit: integer(),
              tier: String.t() | nil,
              resets_at: DateTime.t() | nil
            }
            | nil,
          read_at: DateTime.t() | nil,
          refused_until: DateTime.t() | nil
        }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if Application.get_env(:agent_board, :elevenlabs_account_refresh, true),
      do: send(self(), :refresh)

    {:ok, nil}
  end

  @impl true
  def handle_info(:refresh, state) do
    refresh()
    Process.send_after(self(), :refresh, @every)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    refresh()
    {:noreply, state}
  end

  @doc "Reads the account now and keeps it; a failed read keeps the last one."
  @spec refresh(DateTime.t()) :: :ok
  def refresh(now \\ DateTime.utc_now()) do
    case ElevenLabs.subscription() do
      {:ok, subscription} -> put(%{state() | subscription: subscription, read_at: now})
      {:error, _reason} -> :ok
    end
  end

  @doc "What the board knows about the account."
  @spec snapshot() :: t()
  def snapshot, do: state()

  @doc "Whether the paid voice is spent now (see the module doc)."
  @spec spent?(DateTime.t()) :: boolean()
  def spent?(now \\ DateTime.utc_now()), do: plan_spent?(state(), now) or refused?(state(), now)

  @doc "Whether the plan itself has no characters left before it renews."
  @spec plan_spent?(t(), DateTime.t()) :: boolean()
  def plan_spent?(%{subscription: %{used: used, limit: limit} = sub}, now) when limit > 0,
    do: used >= limit and (is_nil(sub.resets_at) or DateTime.compare(now, sub.resets_at) == :lt)

  def plan_spent?(_state, _now), do: false

  defp refused?(%{refused_until: %DateTime{} = until}, now),
    do: DateTime.compare(now, until) == :lt

  defp refused?(_state, _now), do: false

  @doc """
  A speech was refused for credits: the computer voice speaks for the next
  hour, the activity feed says it once, and the account is read again.
  """
  @spec mark_spent(DateTime.t()) :: :ok
  def mark_spent(now \\ DateTime.utc_now()) do
    unless spent?(now) do
      Activity.record(:tts, :error, "ElevenLabs credits spent: the computer voice speaks for now")
    end

    put(%{state() | refused_until: DateTime.add(now, @refused_for, :second)})
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, :refresh)
    :ok
  end

  @doc false
  def clear, do: :persistent_term.erase(@key)

  defp state,
    do: :persistent_term.get(@key, %{subscription: nil, read_at: nil, refused_until: nil})

  defp put(state), do: :persistent_term.put(@key, state)
end
