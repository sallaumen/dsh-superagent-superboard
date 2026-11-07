defmodule AgentBoardWeb.VoiceConversation do
  @moduledoc """
  The LiveView side of the owner's spoken conversation.

  Lifecycle of one turn (the owner of each transition in brackets):

  | Transition | Owner | Durable record |
  |---|---|---|
  | heard → sent | the `VoiceCommand` hook (silence ends the turn) | none |
  | sent → thinking | `start/2` [this socket]: records the owner turn, starts `{:voice_turn, ref}` | `voice_turns` (owner) |
  | thinking → answered | `finish/3`, only for the current `ref` | `voice_turns` (agent; a proposal when the reply asks for a yes) |
  | thinking → superseded | a newer `start/2` cancels the older job; its result is dropped | — |
  | thinking → timed out | `{:voice_turn_timeout, ref}` after `:voice_turn_timeout_ms` | — |
  | proposed → confirmed/cancelled | `AgentBoard.Conversation.settle/2`, conditional, once | `voice_turns.proposal_status` |

  The reply is spoken in the agent's voice (or the browser's, without an
  ElevenLabs key); `listen: true` asks the browser to open the microphone
  once more after the reply ends, so a question gets its answer without a
  key press. The coding agent never sees this conversation.
  """

  import Phoenix.Component, only: [assign: 3, assign: 2]
  import Phoenix.LiveView, only: [start_async: 3, cancel_async: 2, push_event: 3, push_patch: 2]

  alias AgentBoard.{AI, Conversation}
  alias AgentBoard.Conversation.Agent
  alias AgentBoard.Voice.{Activity, Phrases}
  alias AgentBoardWeb.{BoardNavigation, VoiceCommands, VoiceSpeech}

  @max_text 2_000
  @feed 25

  @doc "The assigns a socket needs before the first turn."
  def mount(socket) do
    # The live feed: every stage, retry and failure of the voice pipeline,
    # pushed by AgentBoard.Voice.Activity over PubSub.
    if Phoenix.LiveView.connected?(socket), do: Activity.subscribe()

    assign(socket,
      chat_turn: nil,
      voice_turns: Conversation.recent(),
      voice_activity: Enum.take(Activity.recent(), @feed)
    )
  end

  @doc "A new activity event reached this board: newest first, bounded."
  def activity(socket, event),
    do: assign(socket, :voice_activity, Enum.take([event | socket.assigns.voice_activity], @feed))

  @doc "A finished utterance (spoken or typed): record it and start thinking."
  def start(socket, text) do
    text = text |> String.trim() |> String.slice(0, @max_text)

    if text == "" do
      socket
    else
      socket = cancel(socket, "substituída por uma fala nova")
      repo = socket.assigns.repo
      {:ok, turn} = Conversation.record("owner", text, repository_id: repo && repo.id)

      ref = System.unique_integer([:positive])
      Process.send_after(self(), {:voice_turn_timeout, ref}, timeout())
      ctx = socket |> context() |> Map.put(:turn_id, turn.id)
      words = text |> String.split() |> length()
      Activity.record(:turn, :start, "fala recebida (#{words} palavras), pensando", turn: turn.id)

      socket
      |> assign(
        chat_turn: %{ref: ref, turn_id: turn.id, started: System.monotonic_time(:millisecond)},
        voice_turns: Conversation.recent()
      )
      |> push_event("voice_thinking", %{})
      |> push_event("voice_chat_clear", %{})
      |> start_async({:voice_turn, ref}, fn -> respond(text, ctx) end)
    end
  end

  @doc "Applies a turn's result, only if it is still the current turn."
  def finish(socket, ref, outcome) do
    case socket.assigns.chat_turn do
      %{ref: ^ref} = turn ->
        socket
        |> assign(chat_turn: nil, voice_turns: Conversation.recent())
        |> apply_outcome(turn, System.monotonic_time(:millisecond) - turn.started, outcome)

      _ ->
        # A late result of a turn that was superseded, cancelled or timed out.
        socket
    end
  end

  defp apply_outcome(socket, turn, ms, {:ok, result}) do
    status = if result.action == "error", do: :error, else: :ok
    Activity.record(:turn, status, "respondeu (#{result.action})", turn: turn.turn_id, ms: ms)

    socket
    |> speak(result.reply, result.listen)
    |> effect(result.effect)
    |> start_async({:voice_compact, turn.ref}, fn -> Conversation.compact() end)
  end

  defp apply_outcome(socket, turn, ms, {:exit, reason}) do
    Activity.record(:turn, :error, "o processo da resposta caiu",
      turn: turn.turn_id,
      ms: ms,
      reason: exit_reason(reason)
    )

    speak(socket, Phrases.ai_failed(language(socket), :exit), false)
  end

  @doc "The turn took too long: drop it and say so."
  def timeout(socket, ref) do
    case socket.assigns.chat_turn do
      %{ref: ^ref} = turn ->
        Activity.record(:turn, :error, "sem resposta a tempo, desisti",
          turn: turn.turn_id,
          ms: timeout()
        )

        socket
        |> cancel_async({:voice_turn, ref})
        |> assign(:chat_turn, nil)
        |> speak(Phrases.too_slow(language(socket)), false)

      _ ->
        socket
    end
  end

  @doc "The owner asked to forget the conversation from the UI."
  def forget(socket) do
    :ok = Conversation.clear()
    socket |> cancel() |> assign(:voice_turns, [])
  end

  @doc "The owner pressed Escape while the agent was thinking: drop the turn quietly."
  def cancel_turn(socket), do: cancel(socket, "cancelada com Esc")

  defp cancel(socket, why \\ nil)

  defp cancel(%{assigns: %{chat_turn: %{ref: ref} = turn}} = socket, why) do
    if why, do: Activity.record(:turn, :info, "resposta #{why}", turn: turn.turn_id)
    socket |> cancel_async({:voice_turn, ref}) |> assign(:chat_turn, nil)
  end

  defp cancel(socket, _why), do: socket

  defp exit_reason({%{__exception__: true} = e, _stack}), do: e
  defp exit_reason(reason), do: reason

  # Without a model the conversation still takes the simple commands.
  defp respond(text, %{ai_status: :not_configured} = ctx) do
    %{result: result, path: path} = VoiceCommands.resolve(text, ctx.assigns)

    reply = result.text

    Conversation.record("agent", reply,
      repository_id: ctx.repo && ctx.repo.id,
      action: "command"
    )

    %{reply: reply, action: "command", effect: path && {:path, path}, listen: false}
  end

  defp respond(text, ctx), do: Agent.respond(text, ctx)

  defp context(socket) do
    a = socket.assigns

    %{
      language: language(socket),
      repo: a.repo,
      repos: a.repos,
      board: a.board,
      sync_event: a.sync_event,
      open_task: a.conversation,
      ai_status: AI.status(),
      assigns: Map.take(a, [:repo, :repos, :board, :sync_event, :conversation])
    }
  end

  defp speak(socket, text, listen) do
    voice = socket.assigns.voice

    if voice.configured do
      push_event(socket, "voice_play", %{
        url: VoiceSpeech.url(text, voice.id),
        listen: listen,
        text: text
      })
    else
      push_event(socket, "speak", %{
        text: VoiceSpeech.text(text),
        lang: voice.language,
        rate: voice.speed,
        listen: listen
      })
    end
  end

  defp effect(socket, {:open_task, task}) do
    if socket.assigns.repo && socket.assigns.repo.id == task.repository_id,
      do: BoardNavigation.open_task(socket, task.id),
      else: socket
  end

  defp effect(socket, {:select_repository, repo}),
    do: push_patch(socket, to: BoardNavigation.path(repo))

  defp effect(socket, {:path, path}), do: push_patch(socket, to: path)
  # A spoken "mais devagar" / "mais alto" changed a setting: the panel and
  # the player (data-volume) follow at once.
  defp effect(socket, :voice_changed) do
    voice = socket.assigns.voice

    assign(socket, :voice, %{
      voice
      | speed: AgentBoard.Voice.speed(),
        volume: AgentBoard.Voice.volume()
    })
  end

  defp effect(socket, _effect), do: socket

  defp language(socket), do: socket.assigns.voice.language

  defp timeout, do: Application.get_env(:agent_board, :voice_turn_timeout_ms, 45_000)
end
