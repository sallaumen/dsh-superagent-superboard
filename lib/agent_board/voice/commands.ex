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
          say: %{"pt-BR" => "Status", "en-US" => "Status"},
          does: gettext_noop("the board in one sentence, right away"),
          mode: :local,
          try: true
        },
        %{
          say: %{"pt-BR" => "Como está o quadro?", "en-US" => "How is the board?"},
          does: gettext_noop("what needs you, what is running and what is in the queue"),
          mode: :read,
          try: true
        },
        %{
          say: %{"pt-BR" => "O que mudou hoje?", "en-US" => "What changed today?"},
          does: gettext_noop("merges, new tasks and runs that ended today"),
          mode: :read,
          try: true
        },
        %{
          say: %{"pt-BR" => "Como foi a semana?", "en-US" => "How was the week?"},
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
          say: %{"pt-BR" => "O que está rodando agora?", "en-US" => "What is running now?"},
          does: gettext_noop("each run, for how long and its last report"),
          mode: :read,
          try: true
        },
        %{
          say: %{"pt-BR" => "O agente está vivo?", "en-US" => "Is the agent alive?"},
          does: gettext_noop("the agent's last signal and how many runs it has"),
          mode: :read,
          try: true
        },
        %{
          say: %{"pt-BR" => "O que terminou hoje?", "en-US" => "What finished today?"},
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
          say: %{"pt-BR" => "Por que a 42 está bloqueada?", "en-US" => "Why is 42 blocked?"},
          does: gettext_noop("the block or the question in the workpad, the report and the PR"),
          mode: :read,
          try: false
        },
        %{
          say: %{"pt-BR" => "Como está a tarefa 42?", "en-US" => "How is task 42?"},
          does: gettext_noop("state, for how long, the run, the PR and the CI"),
          mode: :read,
          try: false
        },
        %{
          say: %{"pt-BR" => "Abre a tarefa 42", "en-US" => "Open task 42"},
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
          say: %{"pt-BR" => "O que está falhando?", "en-US" => "What is failing?"},
          does: gettext_noop("red CI, blocked tasks, runs that stopped and sync errors"),
          mode: :read,
          try: true
        },
        %{
          say: %{"pt-BR" => "Teve erro na voz?", "en-US" => "Any errors in the voice?"},
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
          say: %{"pt-BR" => "Acha a tarefa sobre volume", "en-US" => "Find the task about volume"},
          does: gettext_noop("searches the title and description of tasks, and the PRs"),
          mode: :read,
          try: false
        },
        %{
          say: %{
            "pt-BR" => "Tem algum bug de login aberto?",
            "en-US" => "Is there an open login bug?"
          },
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
          say: %{
            "pt-BR" => "Cria uma tarefa no arena rogue para mostrar o volume",
            "en-US" => "Create a task in arena rogue to show the volume"
          },
          does: gettext_noop("refines the request and asks, naming the repository and the title"),
          mode: :confirm,
          try: false
        },
        %{
          say: %{
            "pt-BR" => "Cria direto: corrigir o botão de salvar",
            "en-US" => "Create directly: fix the save button"
          },
          does:
            gettext_noop(
              "creates at once, without asking; \"undo\" closes the issue for 10 minutes"
            ),
          mode: :direct,
          try: false
        },
        %{
          say: %{
            "pt-BR" => "Pergunta pro agente da 12 se ele rodou os testes",
            "en-US" => "Ask the agent on 12 whether it ran the tests"
          },
          does:
            gettext_noop(
              "comments on the issue after your yes and speaks the answer when it comes"
            ),
          mode: :confirm,
          try: false
        },
        %{
          say: %{"pt-BR" => "Para a 7 / Arquiva a 7", "en-US" => "Stop 7 / Archive 7"},
          does: gettext_noop("says which one and what happens, and asks"),
          mode: :confirm,
          try: false
        },
        %{
          say: %{"pt-BR" => "Desfaz", "en-US" => "Undo"},
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
          say: %{"pt-BR" => "Repete", "en-US" => "Repeat"},
          does: gettext_noop("says the last answer again"),
          mode: :local,
          try: false
        },
        %{
          say: %{
            "pt-BR" => "Mais devagar / mais rápido / mais alto / mais baixo",
            "en-US" => "Slower / faster / louder / quieter"
          },
          does: gettext_noop("adjusts the voice and confirms in the new one"),
          mode: :local,
          try: false
        },
        %{
          say: %{"pt-BR" => "Muda para o arena rogue", "en-US" => "Switch to arena rogue"},
          does: gettext_noop("switches project"),
          mode: :read,
          try: false
        },
        %{
          say: %{"pt-BR" => "Esquece a conversa", "en-US" => "Forget the conversation"},
          does: gettext_noop("erases the conversation's memory"),
          mode: :read,
          try: false
        },
        %{
          say: %{"pt-BR" => "Ajuda", "en-US" => "Help"},
          does: gettext_noop("opens this list"),
          mode: :local,
          try: false
        }
      ]
    }
  ]

  @doc """
  The groups of commands, in the order the panel shows them, with what to
  say in `language` (`"en-US"`, anything else is Portuguese). The titles and
  descriptions are English msgids: the screen translates them.
  """
  @spec groups(String.t()) :: [group()]
  def groups(language \\ "pt-BR") do
    key = if language == "en-US", do: "en-US", else: "pt-BR"

    for group <- @groups do
      %{group | items: Enum.map(group.items, &%{&1 | say: Map.fetch!(&1.say, key)})}
    end
  end

  @doc "Every item, flat, with what to say in `language`."
  @spec items(String.t()) :: [item()]
  def items(language \\ "pt-BR"), do: Enum.flat_map(groups(language), & &1.items)

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
