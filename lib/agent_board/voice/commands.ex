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

  @type mode :: :local | :read | :confirm | :direct
  @type item :: %{say: String.t(), does: String.t(), mode: mode(), try: boolean()}
  @type group :: %{id: atom(), title: String.t(), items: [item()]}

  # The kinds of read `look` can ask for; the `lookup` enum of the schema.
  @lookups ~w(task runs failures search activity)

  @groups [
    %{
      id: :status,
      title: "Status e resumo",
      items: [
        %{say: "Status", does: "o quadro em uma frase, na hora", mode: :local, try: true},
        %{
          say: "Como está o quadro?",
          does: "o que precisa de você, o que roda e o que está na fila",
          mode: :read,
          try: true
        },
        %{
          say: "O que mudou hoje?",
          does: "merges, tarefas novas e execuções terminadas hoje",
          mode: :read,
          try: true
        },
        %{
          say: "Como foi a semana?",
          does: "os merges e as tarefas dos últimos 7 dias",
          mode: :read,
          try: true
        }
      ]
    },
    %{
      id: :runs,
      title: "Execuções do agente",
      items: [
        %{
          say: "O que está rodando agora?",
          does: "cada execução, há quanto tempo e o último relato",
          mode: :read,
          try: true
        },
        %{
          say: "O agente está vivo?",
          does: "o último sinal do agente e quantas execuções ele tem",
          mode: :read,
          try: true
        },
        %{
          say: "O que terminou hoje?",
          does: "as execuções encerradas nas últimas 24 horas e como terminaram",
          mode: :read,
          try: true
        }
      ]
    },
    %{
      id: :task,
      title: "Analisar uma tarefa",
      items: [
        %{
          say: "Por que a 42 está bloqueada?",
          does: "o bloqueio ou a pergunta do workpad, o relato e o PR",
          mode: :read,
          try: false
        },
        %{
          say: "Como está a tarefa 42?",
          does: "estado, há quanto tempo, a execução, o PR e o CI",
          mode: :read,
          try: false
        },
        %{say: "Abre a tarefa 42", does: "mostra a conversa da tarefa", mode: :read, try: false}
      ]
    },
    %{
      id: :failures,
      title: "Bugs e falhas",
      items: [
        %{
          say: "O que está falhando?",
          does: "CI vermelho, tarefas bloqueadas, execuções que pararam e erros de sync",
          mode: :read,
          try: true
        },
        %{
          say: "Teve erro na voz?",
          does: "os erros recentes da própria voz (transcrição, modelo, reprodução)",
          mode: :read,
          try: true
        }
      ]
    },
    %{
      id: :search,
      title: "Buscar",
      items: [
        %{
          say: "Acha a tarefa sobre volume",
          does: "busca no título e na descrição das tarefas e nos PRs",
          mode: :read,
          try: false
        },
        %{
          say: "Tem algum bug de login aberto?",
          does: "a mesma busca, com o estado de cada achado",
          mode: :read,
          try: false
        }
      ]
    },
    %{
      id: :requests,
      title: "Pedidos (escrevem no GitHub)",
      items: [
        %{
          say: "Cria uma tarefa no arena rogue para mostrar o volume",
          does: "refina o pedido, diz o título e pergunta \"Posso criar?\"",
          mode: :confirm,
          try: false
        },
        %{
          say: "Cria direto: corrigir o botão de salvar",
          does: "cria na hora, sem perguntar; \"desfaz\" fecha a issue por 10 minutos",
          mode: :direct,
          try: false
        },
        %{
          say: "Pergunta pro agente da 12 se ele rodou os testes",
          does: "comenta na issue depois do seu sim e fala a resposta quando chegar",
          mode: :confirm,
          try: false
        },
        %{
          say: "Para a 7 / Arquiva a 7",
          does: "diz qual é e pergunta \"Posso?\"",
          mode: :confirm,
          try: false
        },
        %{
          say: "Desfaz",
          does: "fecha a última tarefa que a voz criou, nos últimos 10 minutos",
          mode: :local,
          try: false
        }
      ]
    },
    %{
      id: :conversation,
      title: "A conversa e a voz",
      items: [
        %{say: "Repete", does: "fala de novo a última resposta", mode: :local, try: false},
        %{
          say: "Mais devagar / mais rápido / mais alto / mais baixo",
          does: "ajusta a voz e confirma já na voz nova",
          mode: :local,
          try: false
        },
        %{say: "Muda para o arena rogue", does: "troca de projeto", mode: :read, try: false},
        %{
          say: "Esquece a conversa",
          does: "apaga a memória da conversa",
          mode: :read,
          try: false
        },
        %{say: "Ajuda", does: "abre esta lista", mode: :local, try: false}
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
  def mode_label(:local), do: "na hora"
  def mode_label(:read), do: "só lê"
  def mode_label(:confirm), do: "pede seu sim"
  def mode_label(:direct), do: "faz na hora"
end
