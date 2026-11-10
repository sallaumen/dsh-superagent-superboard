defmodule AgentBoard.Voice.Commands do
  @moduledoc """
  What the owner can ask the voice agent, as one list.

  The list is the single source for the "O que posso pedir" panel and the
  spoken help. The model prompt (`:voice_agent` in `AgentBoard.AI.Registry`)
  describes the same actions; `lookups/0` here is checked against its schema
  by a test, so a new read cannot exist in one place only.

  Each item says how it runs:

    * `:local` - recognized on the board, no model, no cost (a short phrase).
    * `:read` - the model picks it and the board reads its own data; nothing
      is written.
    * `:confirm` - a write that waits for the owner's spoken yes.
    * `:direct` - a write done at once because the owner said so ("cria
      direto"); "desfaz" undoes it for 10 minutes.

  `try: true` marks an example that can be sent as it is (no task number to
  fill in), so the panel offers it as a button.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  @type mode :: :local | :read | :confirm | :direct
  @type item :: %{say: String.t(), does: String.t(), mode: mode(), try: boolean()}
  @type group :: %{id: atom(), title: String.t(), items: [item()]}

  # The kinds of read `look` can ask for; the `lookup` enum of the schema.
  @lookups ~w(task runs failures search activity)

  @groups [
    %{
      id: :status,
      title: gettext_noop("Status and summary"),
      items: [
        %{
          say: "Status",
          does: gettext_noop("the board in one sentence, right away"),
          mode: :local,
          try: true
        },
        %{
          say: "Como está o quadro?",
          does: gettext_noop("what needs you, what is running and what is in the queue"),
          mode: :read,
          try: true
        },
        %{
          say: "O que mudou hoje?",
          does: gettext_noop("merges, new tasks and runs that ended today"),
          mode: :read,
          try: true
        },
        %{
          say: "Como foi a semana?",
          does: gettext_noop("the merges and the tasks of the last 7 days"),
          mode: :read,
          try: true
        }
      ]
    },
    %{
      id: :runs,
      title: gettext_noop("The agent's runs"),
      items: [
        %{
          say: "O que está rodando agora?",
          does: gettext_noop("each run, for how long and its last report"),
          mode: :read,
          try: true
        },
        %{
          say: "O agente está vivo?",
          does: gettext_noop("the agent's last signal and how many runs it has"),
          mode: :read,
          try: true
        },
        %{
          say: "O que terminou hoje?",
          does: gettext_noop("the runs that ended in the last 24 hours and how they ended"),
          mode: :read,
          try: true
        }
      ]
    },
    %{
      id: :task,
      title: gettext_noop("Look into a task"),
      items: [
        %{
          say: "Por que a 42 está bloqueada?",
          does: gettext_noop("the block or the question in the workpad, the report and the PR"),
          mode: :read,
          try: false
        },
        %{
          say: "Como está a tarefa 42?",
          does: gettext_noop("state, for how long, the run, the PR and the CI"),
          mode: :read,
          try: false
        },
        %{
          say: "Abre a tarefa 42",
          does: gettext_noop("shows the task's conversation"),
          mode: :read,
          try: false
        }
      ]
    },
    %{
      id: :failures,
      title: gettext_noop("Bugs and failures"),
      items: [
        %{
          say: "O que está falhando?",
          does: gettext_noop("red CI, blocked tasks, runs that stopped and sync errors"),
          mode: :read,
          try: true
        },
        %{
          say: "Teve erro na voz?",
          does: gettext_noop("the voice's own recent errors (transcription, model, playback)"),
          mode: :read,
          try: true
        }
      ]
    },
    %{
      id: :search,
      title: gettext_noop("Search"),
      items: [
        %{
          say: "Acha a tarefa sobre volume",
          does: gettext_noop("searches the title and description of tasks, and the PRs"),
          mode: :read,
          try: false
        },
        %{
          say: "Tem algum bug de login aberto?",
          does: gettext_noop("the same search, with the state of each result"),
          mode: :read,
          try: false
        }
      ]
    },
    %{
      id: :requests,
      title: gettext_noop("Requests (they write to GitHub)"),
      items: [
        %{
          say: "Cria uma tarefa no arena rogue para mostrar o volume",
          does: gettext_noop("refines the request and asks, naming the repository and the title"),
          mode: :confirm,
          try: false
        },
        %{
          say: "Cria direto: corrigir o botão de salvar",
          does:
            gettext_noop(
              "creates at once, without asking; \"desfaz\" closes the issue for 10 minutes"
            ),
          mode: :direct,
          try: false
        },
        %{
          say: "Pergunta pro agente da 12 se ele rodou os testes",
          does:
            gettext_noop(
              "comments on the issue after your yes and speaks the answer when it comes"
            ),
          mode: :confirm,
          try: false
        },
        %{
          say: "Para a 7 / Arquiva a 7",
          does: gettext_noop("says which one and what happens, and asks"),
          mode: :confirm,
          try: false
        },
        %{
          say: "Desfaz",
          does:
            gettext_noop("closes the last task the voice created, within the last 10 minutes"),
          mode: :local,
          try: false
        }
      ]
    },
    %{
      id: :conversation,
      title: gettext_noop("The conversation and the voice"),
      items: [
        %{
          say: "Repete",
          does: gettext_noop("says the last answer again"),
          mode: :local,
          try: false
        },
        %{
          say: "Mais devagar / mais rápido / mais alto / mais baixo",
          does: gettext_noop("adjusts the voice and confirms in the new one"),
          mode: :local,
          try: false
        },
        %{
          say: "Muda para o arena rogue",
          does: gettext_noop("switches project"),
          mode: :read,
          try: false
        },
        %{
          say: "Esquece a conversa",
          does: gettext_noop("erases the conversation's memory"),
          mode: :read,
          try: false
        },
        %{say: "Ajuda", does: gettext_noop("opens this list"), mode: :local, try: false}
      ]
    }
  ]

  @doc "The groups of commands, in the order the panel shows them."
  @spec groups() :: [group()]
  def groups, do: @groups

  @doc "Every item, flat."
  @spec items() :: [item()]
  def items, do: Enum.flat_map(@groups, & &1.items)

  @doc "The kinds of board read the `look` action can ask for."
  @spec lookups() :: [String.t()]
  def lookups, do: @lookups

  @doc "How a mode reads in the list."
  @spec mode_label(mode()) :: String.t()
  def mode_label(:local), do: gettext("right away")
  def mode_label(:read), do: gettext("only reads")
  def mode_label(:confirm), do: gettext("asks for your yes")
  def mode_label(:direct), do: gettext("acts at once")
end
