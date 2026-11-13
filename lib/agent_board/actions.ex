defmodule AgentBoard.Actions do
  @moduledoc """
  The one door for every write the board makes: each action declares its
  risk, the sentence that confirms it with the real values, and the
  function that runs it. The interface, the voice, the API and the board's
  own automatic work all go through `run/4`; nothing else calls the effects
  (a test reads `lib/` and fails on a call outside this module).

  **Risk** (from the Alfred plan, `docs/research/alfred.md`, F2.3):

    * `:green` - only reads (asking for a sync is a read of GitHub).
    * `:yellow` - changes something the board can change back.
    * `:red` - sends something outside, spends money or has no way back.
      It **always** needs a confirmation, and the code refuses it without
      one: `run/4` answers `{:error, {:unconfirmed, phrase}}`, records the
      refusal and runs nothing.

  **A confirmation** is one of:

    * `confirm: phrase` - the person saw or heard exactly this sentence and
      agreed (a confirm button that showed it, a spoken yes to a proposal
      that said it, an API call that echoes the sentence the API answered).
      The sentence is rebuilt from the values at run time; when they changed
      since it was shown (a task renamed, another repository) it no longer
      matches and the action is refused with `{:error, {:phrase_changed,
      phrase}}`.
    * `confirm: {:words, utterance}` - the person's own words ordered it
      without a question, for the two actions that accept that ("cria
      direto" for a voice create, "desfaz" for its undo). The words are
      checked here, never taken from the model's reading.

  An action without a confirmation runs only when it is not red, or when a
  **standing authorization** in the maintainer contract names the actor
  (the automatic retry of a transient failure, by `auto_retry`).

  **Every decision is a row** (`AgentBoard.Actions.Decision`): confirmed,
  automatic or refused, by whom, through which door and when. An executed
  decision is written before the effect and gets its outcome after.

  The paid reads (model calls, ElevenLabs speech) are not actions: they
  change nothing outside the board and have their own gates
  (`AgentBoard.AI.Registry` with `Budget.check/1`, `ElevenLabs.Usage`).
  Neither are the mirror's writes (the sync and the poller store what they
  read) nor the board's own records (events, voice turns, ledgers, caches).
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  require Logger
  import Ecto.Query, warn: false

  alias AgentBoard.Actions.Decision

  alias AgentBoard.{
    AgentAccess,
    AgentControl,
    AutoRetry,
    Board,
    Conversation,
    DailySummary,
    ElevenLabs,
    Executors,
    GitHub,
    Orchestrator,
    Repo,
    Routing,
    Runners,
    Settings,
    Setup,
    Superagents,
    Voice
  }

  alias AgentBoard.Board.{Attachments, PrivateContext, Repository, SplitGraph, Task}
  alias AgentBoard.Intake.IssueBody
  alias AgentBoard.Release
  alias AgentBoard.Superagents.{Leftovers, Policy, RuntimeSync}
  alias AgentBoard.Sync.Worker
  alias AgentBoard.Voice.Phrases

  @type name :: atom()
  @type risk :: :green | :yellow | :red
  @type actor :: %{by: String.t(), via: :ui | :voice | :api | :system}
  @type refusal :: {:unconfirmed | :phrase_changed, String.t()}

  # The order is the inventory's order in the maintainer contract.
  @names [
    :create_tasks,
    :ask_task,
    :share_private_context,
    :stop_task,
    :undo_created_task,
    :archive_task,
    :resume_task,
    :retry_ticket,
    :auto_retry_ticket,
    :release_task,
    :dispatch_task,
    :stop_execution,
    :provision_superagent,
    :install_first_superagent,
    :adopt_superagent,
    :retry_provision_superagent,
    :remove_superagent,
    :sync_agent_runtimes,
    :start_superagent,
    :stop_superagent,
    :pause_superagent,
    :resume_superagent,
    :scale_superagent,
    :apply_agent_policy,
    :set_agent_folder_days,
    :sweep_agent_folders,
    :clean_agent_leftovers,
    :grant_agent_access,
    :revoke_agent_access,
    :dismiss_access_request,
    :start_agent,
    :set_max_workers,
    :add_repository,
    :change_setting,
    :dismiss_summary,
    :forget_conversation,
    :check_setup,
    :sync_now,
    :update_board,
    :restart_board
  ]

  @settings %{
    "volume" => {Voice, :put_volume},
    "speed" => {Voice, :put_speed},
    "style" => {Voice, :put_style},
    "pause" => {Voice, :put_pause},
    "earcons" => {Voice, :put_earcons},
    "input" => {Voice, :put_input},
    "replies" => {Voice, :put_replies}
  }

  # ---- the catalog ------------------------------------------------------------

  @doc "Every action name, in the inventory's order."
  @spec names() :: [name()]
  def names, do: @names

  @doc "The registry as data: name, risk, what it does, and its standing authorization."
  @spec catalog() :: [map()]
  def catalog, do: Enum.map(@names, &Map.put(spec(&1), :name, &1))

  @doc "The risk of an action."
  @spec risk(name()) :: risk()
  def risk(name), do: spec(name).risk

  defp spec(:create_tasks),
    do: %{risk: :red, does: "abre issues no GitHub que mencionam o agente", words: :direct}

  defp spec(:ask_task), do: %{risk: :red, does: "comenta na issue com a menção ao agente"}

  defp spec(:share_private_context),
    do: %{risk: :red, does: "comenta na issue o caminho do contexto privado, sem a menção"}

  defp spec(:stop_task), do: %{risk: :red, does: "fecha a issue e marca a tarefa como parada"}

  defp spec(:undo_created_task),
    do: %{risk: :red, does: "fecha a issue que a voz acabou de abrir", words: :undo}

  defp spec(:archive_task), do: %{risk: :yellow, does: "tira a tarefa do quadro; Retomar desfaz"}
  defp spec(:resume_task), do: %{risk: :yellow, does: "devolve a tarefa à fila do quadro"}

  defp spec(:retry_ticket),
    do: %{risk: :red, does: "pede ao runner uma rodada nova do ticket; gasta tokens do executor"}

  defp spec(:auto_retry_ticket),
    do: %{
      risk: :red,
      does: "a mesma rodada nova, pedida pelo board depois de uma falha passageira",
      standing: %{
        by: "auto_retry",
        granted: "2026-11-07",
        where: "docs/maintainer-contract.md, Automatic retry"
      }
    }

  defp spec(:release_task),
    do: %{
      risk: :red,
      does: "comenta a menção que faz o agente começar a tarefa que esperava; gasta tokens",
      standing: %{
        by: "release",
        granted: "2026-11-09",
        where: "docs/decisions/0005-o-board-libera-tarefas-em-ordem.md"
      }
    }

  defp spec(:dispatch_task),
    do: %{
      risk: :red,
      does: "inicia o Claude Code ou o Codex num worktree e gasta a assinatura do dono"
    }

  defp spec(:stop_execution),
    do: %{risk: :red, does: "encerra o processo de uma execução local e deixa a tarefa bloqueada"}

  defp spec(:provision_superagent),
    do: %{risk: :red, does: "cria profile, porta, state e setup de um superagent novo"}

  defp spec(:install_first_superagent),
    do: %{
      risk: :red,
      does:
        "instala o primeiro superagent desta máquina: baixa o código do agente se faltar, cria o profile, liga e configura"
    }

  defp spec(:adopt_superagent),
    do: %{
      risk: :red,
      does: "passa a acompanhar um superagent já instalado nesta máquina; liga se estiver parado"
    }

  defp spec(:retry_provision_superagent),
    do: %{risk: :red, does: "provisiona de novo um superagent cuja tentativa falhou"}

  defp spec(:remove_superagent),
    do: %{risk: :red, does: "para o superagent e arquiva profile/state; o projeto sai do board"}

  defp spec(:sync_agent_runtimes),
    do: %{risk: :red, does: "atualiza o Harness dos projetos registrados e ociosos desta máquina"}

  defp spec(:start_superagent),
    do: %{risk: :red, does: "inicia o superagent DeepSeek de um projeto"}

  defp spec(:stop_superagent),
    do: %{risk: :red, does: "para o superagent DeepSeek de um projeto"}

  defp spec(:pause_superagent),
    do: %{risk: :yellow, does: "pausa novas tarefas do superagent sem matar o processo"}

  defp spec(:resume_superagent),
    do: %{risk: :yellow, does: "retoma novas tarefas do superagent"}

  defp spec(:scale_superagent),
    do: %{risk: :yellow, does: "muda o limite de sessões simultâneas do superagent"}

  defp spec(:set_agent_folder_days),
    do: %{
      risk: :yellow,
      does: "muda por quantos dias o projeto guarda as pastas de tickets encerrados"
    }

  defp spec(:sweep_agent_folders),
    do: %{
      risk: :red,
      does: "remove as pastas de tickets encerrados há mais dias que a retenção do projeto",
      standing: %{
        by: "folder_retention",
        granted: "2026-11-12",
        where: "docs/maintainer-contract.md, Ended tickets' folders"
      }
    }

  defp spec(:clean_agent_leftovers),
    do: %{
      risk: :red,
      does: "remove todas as pastas de tickets encerrados e fecha os PRs órfãos do agente"
    }

  defp spec(:apply_agent_policy),
    do: %{
      risk: :yellow,
      does: "troca as instruções do superagent pela política do board, com as regras do projeto"
    }

  defp spec(:grant_agent_access),
    do: %{
      risk: :red,
      does: "libera uma pessoa para acionar o superagent; as menções dela gastam tokens"
    }

  defp spec(:revoke_agent_access),
    do: %{risk: :red, does: "tira uma pessoa da lista do superagent; tickets dela podem parar"}

  defp spec(:dismiss_access_request),
    do: %{risk: :yellow, does: "deixa um pedido de acesso de lado até uma nova menção"}

  defp spec(:start_agent),
    do: %{risk: :red, does: "liga o orquestrador nesta máquina e desfaz um stop de propósito"}

  defp spec(:set_max_workers),
    do: %{risk: :yellow, does: "muda o teto de workers do runner; − e + desfazem"}

  defp spec(:add_repository), do: %{risk: :yellow, does: "passa a acompanhar um repositório"}

  defp spec(:change_setting),
    do: %{
      risk: :yellow,
      does: "muda uma preferência do board (a voz, o resumo do dia, o despacho)"
    }

  defp spec(:dismiss_summary), do: %{risk: :yellow, does: "tira o resumo do dia da tela"}

  defp spec(:forget_conversation),
    do: %{risk: :red, does: "apaga a memória da conversa por voz, sem volta"}

  defp spec(:check_setup),
    do: %{risk: :green, does: "verifica o setup com leituras gratuitas e guarda o resultado"}

  defp spec(:sync_now), do: %{risk: :green, does: "pede uma sincronização (lê o GitHub)"}

  defp spec(:update_board),
    do: %{risk: :yellow, does: "avança este checkout para a origin/main (git volta)"}

  defp spec(:restart_board), do: %{risk: :yellow, does: "reinicia o servidor do board"}

  # ---- the sentences ------------------------------------------------------------

  @doc """
  The sentence that confirms an action, with the real values: what, for
  whom, where. The screen shows it and the voice says it, in the voice
  language (`pt-BR` default, `en-US`); `AgentBoard.Voice.Speakable` only
  reads `#12` as "12" and a slug as words.
  """
  @spec phrase(name(), map(), String.t()) :: String.t()
  def phrase(name, params, lang \\ "pt-BR")

  def phrase(:create_tasks, %{repository: repo, requests: requests}, lang),
    do: create_phrase(repo, requests, lang) <> held_note(requests, lang)

  def phrase(:release_task, %{task: %{number: number}, repository: repo}, "en-US") do
    "Call the agent on ##{number} in #{repo_name(repo)}? " <>
      "It starts now, even if a dependency is still open."
  end

  def phrase(:release_task, %{task: %{number: number}, repository: repo}, _lang) do
    "Chamar o agente na ##{number} do #{repo_name(repo)}? " <>
      "Ele começa agora, mesmo que alguma dependência siga aberta."
  end

  def phrase(:ask_task, %{task: task, question: question}, "en-US"),
    do:
      "Ask the agent on task ##{task.number}: #{q(question)}#{ask_mark(question)} " <>
        "The board comments on the GitHub issue."

  def phrase(:ask_task, %{task: task, question: question}, _lang),
    do:
      "Perguntar ao agente na tarefa ##{task.number}: #{q(question)}#{ask_mark(question)} " <>
        "O board comenta na issue do GitHub."

  def phrase(:share_private_context, %{task: task, repository: repo, dir: dir}, "en-US"),
    do:
      "Comment on task ##{task.number} the path of its private context, " <>
        "#{q(PrivateContext.shared_path(repo, dir))}? Only the path goes to GitHub, without calling the agent."

  def phrase(:share_private_context, %{task: task, repository: repo, dir: dir}, _lang),
    do:
      "Comentar na tarefa ##{task.number} o caminho do seu contexto privado, " <>
        "#{q(PrivateContext.shared_path(repo, dir))}? Só o caminho vai ao GitHub, sem chamar o agente."

  def phrase(:stop_task, %{task: task}, "en-US"),
    do:
      "Stop task ##{task.number}, #{q(short(task.title))}? The board closes the issue and " <>
        "marks the task stopped; a step the agent already started finishes first."

  def phrase(:stop_task, %{task: task}, _lang),
    do:
      "Parar a tarefa ##{task.number}, #{q(short(task.title))}? O board fecha a issue e " <>
        "marca a tarefa como parada; um passo que o agente já começou termina antes."

  def phrase(:undo_created_task, %{task: task}, "en-US"),
    do:
      "Undo task ##{task.number}, #{q(short(task.title))}? The board closes the issue it just opened."

  def phrase(:undo_created_task, %{task: task}, _lang),
    do:
      "Desfazer a tarefa ##{task.number}, #{q(short(task.title))}? " <>
        "O board fecha a issue que acabou de abrir."

  def phrase(:stop_execution, %{task: task, execution: execution}, "en-US"),
    do:
      "Stop the #{executor_name(execution.executor)} execution on task ##{task.number}? " <>
        "The process is killed and the partial result stays in Execuções."

  def phrase(:stop_execution, %{task: task, execution: execution}, _lang),
    do:
      "Parar a execução do #{executor_name(execution.executor)} na tarefa ##{task.number}? " <>
        "O processo é encerrado e o resultado parcial fica em Execuções."

  def phrase(:sync_agent_runtimes, %{targets: targets}, lang) do
    names = targets |> Map.values() |> Enum.sort() |> Enum.join(", ")

    if lang == "en-US",
      do: "Update when the agents and their queues are idle: " <> names,
      else: "Atualizar quando os agentes e suas filas estiverem livres: " <> names
  end

  def phrase(:start_superagent, %{superagent: superagent}, "en-US"),
    do:
      "Start DeepSeek on #{project(superagent)}? The superagent #{superagent.profile} " <>
        "listens on port #{superagent.port} and starts taking issues."

  def phrase(:start_superagent, %{superagent: superagent}, _lang),
    do:
      "Ligar o DeepSeek em #{project(superagent)}? O superagent #{superagent.profile} " <>
        "fica na porta #{superagent.port} e começa a pegar issues."

  def phrase(:stop_superagent, %{superagent: superagent}, "en-US"),
    do:
      "Stop DeepSeek on #{project(superagent)}? In-flight work is interrupted; the state is kept."

  def phrase(:stop_superagent, %{superagent: superagent}, _lang),
    do:
      "Parar o DeepSeek em #{project(superagent)}? O trabalho em andamento é interrompido e o estado fica guardado."

  def phrase(:pause_superagent, %{superagent: superagent}, "en-US"),
    do: "Pause new work on #{project(superagent)}? The process stays alive."

  def phrase(:pause_superagent, %{superagent: superagent}, _lang),
    do: "Pausar novas tarefas em #{project(superagent)}? O processo continua vivo."

  def phrase(:resume_superagent, %{superagent: superagent}, "en-US"),
    do: "Resume new work on #{project(superagent)}?"

  def phrase(:resume_superagent, %{superagent: superagent}, _lang),
    do: "Retomar novas tarefas em #{project(superagent)}?"

  def phrase(:apply_agent_policy, %{superagent: superagent}, "en-US"),
    do: "Apply the board's policy to the agent of #{project(superagent)}?"

  def phrase(:apply_agent_policy, %{superagent: superagent}, _lang),
    do: "Aplicar a política do board ao agente de #{project(superagent)}?"

  def phrase(:set_agent_folder_days, %{superagent: superagent, days: :never}, "en-US"),
    do: "Keep the folders of ended tickets of #{project(superagent)} until you remove them?"

  def phrase(:set_agent_folder_days, %{superagent: superagent, days: :never}, _lang),
    do: "Guardar as pastas de tickets encerrados de #{project(superagent)} até você remover?"

  def phrase(:set_agent_folder_days, %{superagent: superagent, days: days}, "en-US"),
    do: "Keep the folders of ended tickets of #{project(superagent)} for #{days} days?"

  def phrase(:set_agent_folder_days, %{superagent: superagent, days: days}, _lang),
    do: "Guardar as pastas de tickets encerrados de #{project(superagent)} por #{days} dias?"

  def phrase(:sweep_agent_folders, %{superagent: superagent, days: days}, "en-US"),
    do:
      "Daily retention on #{project(superagent)}: remove the folders of tickets that ended " <>
        "more than #{days} days ago."

  def phrase(:sweep_agent_folders, %{superagent: superagent, days: days}, _lang),
    do:
      "Retenção diária em #{project(superagent)}: remover as pastas de tickets encerrados " <>
        "há mais de #{days} dias."

  def phrase(:clean_agent_leftovers, %{superagent: superagent}, "en-US"),
    do:
      "Remove now every folder of an ended ticket of #{project(superagent)} and close the pull " <>
        "requests its agent left without a merge? Tickets, issues and branches stay; a folder " <>
        "with uncommitted changes stays too. The folders do not come back."

  def phrase(:clean_agent_leftovers, %{superagent: superagent}, _lang),
    do:
      "Remover agora todas as pastas de tickets encerrados de #{project(superagent)} e fechar " <>
        "os pull requests que o agente deixou sem merge? Tickets, issues e branches ficam; " <>
        "pasta com mudança não commitada também fica. As pastas não voltam."

  def phrase(:scale_superagent, %{superagent: superagent, workers: workers}, "en-US"),
    do: "Change #{project(superagent)} from #{superagent.max_workers} to #{workers} workers?"

  def phrase(:scale_superagent, %{superagent: superagent, workers: workers}, _lang),
    do:
      "Mudar o limite de sessões de #{project(superagent)} de #{superagent.max_workers} para #{workers}?"

  def phrase(:grant_agent_access, %{superagent: superagent, login: login} = params, "en-US") do
    "Allow @#{login} on #{project(superagent)}? Each mention of the bot by this person starts " <>
      "work, spends DeepSeek tokens, and the agent may merge without human review." <>
      rerun_text(params, "en-US")
  end

  def phrase(:grant_agent_access, %{superagent: superagent, login: login} = params, _lang) do
    "Liberar @#{login} em #{project(superagent)}? Cada menção dessa pessoa ao bot abre trabalho, " <>
      "gasta tokens do DeepSeek, e o agente pode fazer merge sem revisão humana." <>
      rerun_text(params, "pt-BR")
  end

  def phrase(:revoke_agent_access, %{superagent: superagent, login: login}, "en-US"),
    do:
      "Remove @#{login} from #{project(superagent)}? New mentions on issues without a ticket " <>
        "are ignored; on issues with a ticket the agent may still weigh them as a follow-up. " <>
        "Open tickets from this person may be refused."

  def phrase(:revoke_agent_access, %{superagent: superagent, login: login}, _lang),
    do:
      "Revogar @#{login} em #{project(superagent)}? Novas menções em issues sem ticket são " <>
        "ignoradas; em issues com ticket, o agente ainda pode avaliá-las como continuação. " <>
        "Tickets abertos dessa pessoa podem ser recusados."

  def phrase(:dismiss_access_request, %{superagent: superagent, login: login}, "en-US"),
    do: "Set aside @#{login}'s request on #{project(superagent)}? A new mention brings it back."

  def phrase(:dismiss_access_request, %{superagent: superagent, login: login}, _lang),
    do:
      "Dispensar o pedido de @#{login} em #{project(superagent)}? Uma nova menção traz o " <>
        "pedido de volta."

  def phrase(:adopt_superagent, %{profile: profile, port: port}, "en-US"),
    do:
      "Add the agent #{profile} (port #{port}) to the board? The board asks it which " <>
        "repository it serves, starts following that repository and keeps the agent running; " <>
        "it is started now if it is stopped. Its configuration is not changed."

  def phrase(:adopt_superagent, %{profile: profile, port: port}, _lang),
    do:
      "Adicionar ao board o agente #{profile} (porta #{port})? O board pergunta a ele de qual " <>
        "repositório é, passa a acompanhar esse repositório e a manter o agente ligado; se " <>
        "estiver parado, é ligado agora. A configuração dele não muda."

  def phrase(:install_first_superagent, %{repository: repo, path: path}, "en-US"),
    do:
      "Install this machine's first DeepSeek agent, for #{repo_name(repo)}? The board " <>
        "downloads and builds the agent's code if this machine does not have it, creates a " <>
        "profile, port and state, starts the agent and sets it up for the repository with the " <>
        "bot's account, using the checkout #{short(path)}. It gives the bot write access to " <>
        "the repository if it lacks it. This takes a few minutes."

  def phrase(:install_first_superagent, %{repository: repo, path: path}, _lang),
    do:
      "Instalar o primeiro agente DeepSeek desta máquina, para #{repo_name(repo)}? O board " <>
        "baixa e compila o código do agente se esta máquina ainda não o tiver, cria profile, " <>
        "porta e state, liga o agente e o configura para o repositório com a conta do bot, " <>
        "usando o checkout #{short(path)}. Dá ao bot acesso de escrita no repositório, se " <>
        "faltar. Leva alguns minutos."

  def phrase(:provision_superagent, %{repository: repo, source: source, path: path}, "en-US"),
    do:
      "Provision DeepSeek for #{repo_name(repo)} from #{source.profile}? The board creates " <>
        "a profile, port and state, uses the checkout #{short(path)}, and gives the bot write " <>
        "access to the repository if it lacks it."

  def phrase(:provision_superagent, %{repository: repo, source: source, path: path}, _lang),
    do:
      "Provisionar o DeepSeek para #{repo_name(repo)} a partir de #{source.profile}? O board " <>
        "cria profile, porta e state, usa o checkout #{short(path)} e dá ao bot acesso de " <>
        "escrita no repositório, se faltar."

  # A first agent that did not come up has no profile it was copied from.
  def phrase(
        :retry_provision_superagent,
        %{superagent: %{source_profile: nil} = superagent},
        "en-US"
      ),
      do:
        "Install #{project(superagent)}'s agent again, this machine's first? The board creates " <>
          "a profile, port and state, uses the checkout " <>
          "#{short(superagent.checkout_path)}, and gives the bot write access if it lacks it."

  def phrase(:retry_provision_superagent, %{superagent: %{source_profile: nil} = superagent}, _),
    do:
      "Instalar de novo o agente de #{project(superagent)}, o primeiro desta máquina? O board " <>
        "cria profile, porta e state, usa o checkout " <>
        "#{short(superagent.checkout_path)} e dá ao bot acesso de escrita, se faltar."

  def phrase(:retry_provision_superagent, %{superagent: superagent}, "en-US"),
    do:
      "Provision #{project(superagent)} again from #{superagent.source_profile}? The board " <>
        "creates a profile, port and state, uses the checkout " <>
        "#{short(superagent.checkout_path)}, and gives the bot write access if it lacks it."

  def phrase(:retry_provision_superagent, %{superagent: superagent}, _lang),
    do:
      "Provisionar de novo #{project(superagent)} a partir de #{superagent.source_profile}? " <>
        "O board cria profile, porta e state, usa o checkout " <>
        "#{short(superagent.checkout_path)} e dá ao bot acesso de escrita, se faltar."

  def phrase(:remove_superagent, %{superagent: superagent}, "en-US"),
    do:
      "Archive DeepSeek from #{project(superagent)}? The agent stops and its profile/state " <>
        "are archived; nothing is deleted."

  def phrase(:remove_superagent, %{superagent: superagent}, _lang),
    do:
      "Arquivar o DeepSeek de #{project(superagent)}? O agente para e o profile/state vão " <>
        "para o arquivo; nada é apagado."

  def phrase(:archive_task, %{task: task}, "en-US"),
    do:
      "Archive task ##{task.number}, #{q(short(task.title))}? It leaves the board and its history stays."

  def phrase(:archive_task, %{task: task}, _lang),
    do:
      "Arquivar a tarefa ##{task.number}, #{q(short(task.title))}? " <>
        "Ela sai do quadro e o histórico fica."

  def phrase(:resume_task, %{task: task}, "en-US"),
    do: "Resume task ##{task.number}, #{q(short(task.title))}? It goes back to the board's queue."

  def phrase(:resume_task, %{task: task}, _lang),
    do:
      "Retomar a tarefa ##{task.number}, #{q(short(task.title))}? Ela volta para a fila do quadro."

  def phrase(:retry_ticket, params, "en-US") do
    target = if params[:number], do: "on ##{params.number}", else: "on the ticket"

    "Ask the agent for another attempt #{target} now? " <>
      "It opens a new round on the ticket and spends the executor's tokens."
  end

  def phrase(:retry_ticket, params, _lang) do
    target = if params[:number], do: "de ##{params.number}", else: "do ticket"

    "Pedir ao agente uma nova tentativa #{target} agora? " <>
      "Ele abre uma rodada nova no ticket e gasta tokens do executor."
  end

  def phrase(:auto_retry_ticket, %{ticket_id: id} = params, _lang),
    do:
      "Nova tentativa automática do ticket #{id} (#{params[:attempt] || "?"} de #{AutoRetry.max_retries()}) " <>
        "depois de uma falha de rede ou do provedor."

  def phrase(:dispatch_task, %{task: task, executor: executor} = params, "en-US") do
    repo = params[:repository] || task.repository
    repo_name = if repo, do: "#{repo.owner}/#{repo.name}", else: "the task's repository"
    ceiling = params[:ceiling_usd]

    fallback_text =
      cond do
        params[:fallback] ->
          " The last executor failed (#{params[:reason]}); this is the confirmed switch."

        params[:retry] ->
          " The last execution failed (#{params[:reason]}); this is a confirmed new attempt."

        true ->
          ""
      end

    ceiling_text =
      if is_number(ceiling) do
        amount = :erlang.float_to_binary(ceiling / 1, decimals: 2)

        " The board opens a worktree and the execution spends up to US$ #{amount} of the subscription."
      else
        " The board opens a worktree and the execution spends the subscription."
      end

    "Dispatch task ##{task.number}, #{q(short(task.title))}, to " <>
      "#{Executors.name(executor)} in #{repo_name}?" <>
      fallback_text <>
      ceiling_text <>
      " Nothing starts without this confirmation."
  end

  def phrase(:dispatch_task, %{task: task, executor: executor} = params, _lang) do
    repo = params[:repository] || task.repository
    repo_name = if repo, do: "#{repo.owner}/#{repo.name}", else: "o repositório da tarefa"
    ceiling = params[:ceiling_usd]

    fallback_text =
      cond do
        params[:fallback] ->
          " O último executor falhou (#{params[:reason]}); esta é a troca confirmada."

        params[:retry] ->
          " A última execução falhou (#{params[:reason]}); esta é uma nova tentativa confirmada."

        true ->
          ""
      end

    ceiling_text =
      if is_number(ceiling) do
        amount =
          :erlang.float_to_binary(ceiling / 1, decimals: 2) |> String.replace(".", ",")

        " O board abre um worktree e a execução gasta até US$ #{amount} da assinatura."
      else
        " O board abre um worktree e a execução gasta a assinatura."
      end

    "Despachar a tarefa ##{task.number}, #{q(short(task.title))}, para o " <>
      "#{Executors.name(executor)} em #{repo_name}?" <>
      fallback_text <>
      ceiling_text <>
      " Nada começa sem esta confirmação."
  end

  def phrase(:start_agent, _params, "en-US"),
    do: "Restart the agent on this machine? If you stopped it on purpose, this undoes the stop."

  def phrase(:start_agent, _params, _lang),
    do: "Religar o agente nesta máquina? Se você o parou de propósito, isso desfaz o stop."

  def phrase(:set_max_workers, %{max: max}, _lang),
    do: "Mudar o limite do executor para #{max} #{if max == 1, do: "agente", else: "agentes"}?"

  def phrase(:add_repository, %{owner: owner, name: name}, _lang),
    do: "Acompanhar #{owner}/#{name} no quadro?"

  def phrase(:change_setting, %{setting: setting, value: value}, _lang),
    do: "Mudar a configuração #{setting} para #{q(setting_value(value))}?"

  def phrase(:dismiss_summary, _params, _lang), do: "Tirar o resumo do dia da tela?"

  def phrase(:forget_conversation, _params, "en-US"),
    do:
      "Forget the whole voice conversation? The agent loses the context, and it can't be undone."

  def phrase(:forget_conversation, _params, _lang),
    do: "Esquecer toda a conversa por voz? O agente perde o contexto, e não há como desfazer."

  def phrase(:check_setup, _params, "en-US"), do: "Check the board setup?"
  def phrase(:check_setup, _params, _lang), do: "Verificar o setup do board?"

  def phrase(:sync_now, _params, _lang), do: "Sincronizar agora com o GitHub?"

  def phrase(:update_board, _params, _lang),
    do: "Atualizar o board com a main e reiniciar o servidor?"

  def phrase(:restart_board, _params, _lang), do: "Reiniciar o servidor do board?"

  @doc """
  Whether the owner's own words order this action without a question:
  "cria direto" / "já cria" / "sem perguntar" for a voice create, "desfaz"
  for its undo. Read here from the words, never from the model's flag.
  """
  @spec direct_order?(name(), String.t() | nil) :: boolean()
  def direct_order?(name, text) when is_binary(text) do
    case Map.get(spec(name), :words) do
      :direct ->
        Regex.match?(
          ~r/\b(direto|diretamente|ja cria|sem perguntar|sem confirmar|directly|right away|without asking)\b/u,
          normalize(text)
        )

      :undo ->
        Regex.match?(~r/\b(desfaz\w*|desfac\w*|undo)\b/u, normalize(text))

      nil ->
        false
    end
  end

  def direct_order?(_name, _text), do: false

  # ---- the actors ---------------------------------------------------------------

  @doc "The owner, through a door: `:ui`, `:voice` or `:api`."
  @spec owner(:ui | :voice | :api) :: actor()
  def owner(via) when via in [:ui, :voice, :api], do: %{by: "owner", via: via}

  @doc "The board itself, by the name of the part that acts (`\"auto_retry\"`)."
  @spec system(String.t()) :: actor()
  def system(by) when is_binary(by), do: %{by: by, via: :system}

  # ---- the gate -----------------------------------------------------------------

  @doc """
  Runs an action through the gate and answers what its function answered,
  or `{:error, {:unconfirmed | :phrase_changed, phrase}}` when the gate
  refused it. Options: `confirm:` (the phrase the person agreed to, or
  `{:words, utterance}`) and `language:` (of that phrase; without it the
  sentence itself says which of the two languages it was shown in).
  """
  @spec run(name(), map(), actor(), keyword()) :: term() | {:error, refusal()}
  def run(name, params, %{by: _, via: _} = actor, opts \\ []) when is_map(params) do
    spec = spec(name)
    confirm = present(Keyword.get(opts, :confirm))
    lang = Keyword.get(opts, :language) || shown_language(name, params, confirm)
    phrase = phrase(name, params, lang)

    case gate(name, spec, actor, confirm, phrase) do
      {:go, decision, evidence, words} ->
        row =
          insert!(name, spec, params, actor, %{
            decision: decision,
            evidence: evidence,
            phrase: phrase,
            words: words
          })

        execute_recorded(name, params, row, lang)

      {:refuse, reason, words} ->
        insert!(name, spec, params, actor, %{
          decision: "refused",
          phrase: phrase,
          words: words,
          detail: Atom.to_string(reason)
        })

        log(name, "refused", actor, Atom.to_string(reason))
        {:error, {reason, phrase}}
    end
  end

  @doc "The person said no to a confirmation: recorded as refused, nothing runs."
  @spec decline(name(), map(), actor(), keyword()) :: :ok
  def decline(name, params, actor, opts \\ []) do
    phrase = phrase(name, params, Keyword.get(opts, :language, "pt-BR"))

    insert!(name, spec(name), params, actor, %{
      decision: "refused",
      phrase: phrase,
      detail: "declined"
    })

    log(name, "refused", actor, "declined")
    :ok
  end

  @doc "The latest decisions, newest first."
  @spec recent(pos_integer()) :: [Decision.t()]
  def recent(limit \\ 20),
    do: Repo.all(from d in Decision, order_by: [desc: d.id], limit: ^limit)

  # The screen shows the sentence in the interface language. Both sentences
  # are rebuilt from the same values, so matching either is the same proof.
  # Portuguese first: a sentence that only exists in Portuguese is the same
  # in both, and must not make the answer English.
  defp shown_language(name, params, confirm) when is_binary(confirm) do
    shown = squish(confirm)

    cond do
      shown == squish(phrase(name, params, "pt-BR")) -> "pt-BR"
      shown == squish(phrase(name, params, "en-US")) -> "en-US"
      true -> "pt-BR"
    end
  end

  defp shown_language(_name, _params, _confirm), do: "pt-BR"

  defp gate(_name, _spec, _actor, confirm, phrase) when is_binary(confirm) do
    if squish(confirm) == squish(phrase),
      do: {:go, "confirmed", "phrase", nil},
      else: {:refuse, :phrase_changed, nil}
  end

  defp gate(name, _spec, _actor, {:words, words}, _phrase) when is_binary(words) do
    if direct_order?(name, words),
      do: {:go, "confirmed", "words", words},
      else: {:refuse, :unconfirmed, words}
  end

  defp gate(_name, %{risk: :red} = spec, actor, nil, _phrase) do
    case spec do
      %{standing: %{by: by}} when by == actor.by -> {:go, "automatic", "standing", nil}
      _ -> {:refuse, :unconfirmed, nil}
    end
  end

  defp gate(_name, _spec, _actor, nil, _phrase), do: {:go, "automatic", nil, nil}

  # The effect answers in the language of the confirmation: what it returns
  # is read by whoever confirmed. `AgentBoardWeb.Gettext` reads the process.
  defp execute_recorded(name, params, row, lang) do
    locale = if lang == "en-US", do: "en", else: "pt_BR"

    {result, {outcome, detail}} =
      Gettext.with_locale(AgentBoardWeb.Gettext, locale, fn ->
        result = execute(name, params)
        {result, outcome(name, result)}
      end)

    finish(row, outcome, detail)
    log(name, row.decision, row, outcome)
    result
  rescue
    exception ->
      finish(row, "error", Exception.message(exception))
      reraise exception, __STACKTRACE__
  end

  # ---- the effects --------------------------------------------------------------

  defp execute(:create_tasks, %{repository: repo, requests: requests} = params) do
    client = github(params)
    requests = route_requests(repo, requests)

    with_files =
      with {:ok, requests} <- with_private(repo, requests, Map.get(params, :private)) do
        with_attachments(repo, requests, Map.get(params, :attachments, []), client)
      end

    case with_files do
      {:ok, ready} -> finish_create_tasks(repo, ready, params, client)
      {:error, results} -> {:ok, results}
    end
  end

  defp execute(:release_task, %{task: task, repository: repo} = params),
    do: Release.call_agent(task, repo, github(params))

  defp execute(:ask_task, %{task: task, question: question} = params),
    do: Board.ask(task, question, github(params))

  defp execute(:share_private_context, %{task: task, repository: repo, dir: dir} = params) do
    path = PrivateContext.shared_path(repo, dir)
    # The comment follows the confirmation's language, which the effect runs in.
    language = if Gettext.get_locale(AgentBoardWeb.Gettext) == "en", do: "en", else: "pt"
    body = IssueBody.private_comment(dir, path, Map.get(params, :language, language))
    GitHub.create_comment(github(params), repo.owner, repo.name, task.number, body)

    {:ok,
     gettext(
       "The path is on the issue. The agent sees it when it reads the issue; to call it now, write in Conversation."
     )}
  rescue
    exception -> {:error, describe(exception)}
  end

  defp execute(name, %{task: task} = params) when name in [:stop_task, :undo_created_task],
    do: Board.stop_task(task, github(params))

  defp execute(:archive_task, %{task: task}), do: Board.archive_task(task)
  defp execute(:resume_task, %{task: task}), do: Board.resume_task(task)

  defp execute(:retry_ticket, %{ticket_id: ticket_id} = params) do
    opts = [repository_id: params[:repository_id], number: params[:number]]
    opts = if params[:client], do: Keyword.put(opts, :client, params.client), else: opts
    AgentControl.retry(ticket_id, opts)
  end

  defp execute(:auto_retry_ticket, %{ticket_id: ticket_id} = params),
    do: Orchestrator.retry(orchestrator(params), ticket_id)

  defp execute(:dispatch_task, %{task: task, executor: executor} = params) do
    opts =
      [ceiling_usd: params[:ceiling_usd], allow_switch: params[:fallback]]
      |> then(fn opts ->
        if params[:launcher], do: Keyword.put(opts, :launcher, params.launcher), else: opts
      end)

    case Runners.dispatch(task, executor, opts) do
      {:ok, execution} ->
        {:ok,
         gettext(
           "Dispatch started on %{executor} (session %{session}). Progress appears under Executions.",
           executor: Executors.name(executor),
           session: execution.session_id || execution.id
         )}

      {:error, reason} ->
        {:error, dispatch_error(reason)}
    end
  end

  defp execute(:stop_execution, %{execution: execution}) do
    case Runners.stop(execution) do
      {:ok, _execution} ->
        {:ok, gettext("Execution stopped. The task is blocked for you to decide.")}

      {:error, :already_finished} ->
        {:error, gettext("The execution has already ended; see the result under Executions.")}

      {:error, :not_running} ->
        {:error, gettext("That execution is no longer active.")}

      {:error, reason} ->
        {:error, gettext("Could not stop the execution: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(
         :provision_superagent,
         %{repository: repository, source: source, path: path} = params
       ) do
    case Superagents.provision(repository, source, %{
           path: path,
           workers: Map.get(params, :workers, 3)
         }) do
      {:ok, superagent} ->
        {:ok,
         gettext(
           "Superagent %{profile} reserved on port %{port}; the status updates on the ticker.",
           profile: superagent.profile,
           port: superagent.port
         )}

      {:error, reason} ->
        {:error, gettext("Could not provision: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:install_first_superagent, %{repository: repository, path: path} = params) do
    case Superagents.provision(repository, :first, %{
           path: path,
           workers: Map.get(params, :workers, 3)
         }) do
      {:ok, superagent} ->
        {:ok,
         gettext(
           "The first agent is installed: %{profile} on port %{port}. The status updates on the ticker.",
           profile: superagent.profile,
           port: superagent.port
         )}

      {:error, reason} ->
        {:error, gettext("Could not install the agent: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:adopt_superagent, %{profile: profile}) do
    with {:ok, %{owner: owner, name: name} = candidate} <- Superagents.adoptable(profile),
         {:ok, _tracked} <- Board.add_repository(owner, name),
         %Repository{} = repository <- Board.find_repository(owner, name) do
      Superagents.adopt(candidate, repository)
    end
    |> case do
      {:ok, superagent} ->
        {:ok,
         gettext("Added: the board now follows %{project} with the agent %{profile}.",
           project: project(superagent),
           profile: superagent.profile
         )}

      {:error, :not_found} ->
        {:error, gettext("That agent is no longer waiting to be added: reload Projects.")}

      {:error, :no_repository} ->
        {:error,
         gettext(
           "The agent does not say which repository it serves: finish its setup in the dsh panel, then add it."
         )}

      {:error, :already_registered} ->
        {:error, gettext("The repository this agent serves already has an agent on the board.")}

      {:error, reason} ->
        {:error, gettext("The agent did not answer: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:retry_provision_superagent, %{superagent: superagent}) do
    case Superagents.retry_provision(superagent) do
      {:ok, _superagent} ->
        {:ok, gettext("Provisioned again; the status updates on the ticker.")}

      {:error, reason} ->
        {:error, gettext("Could not provision: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:remove_superagent, %{superagent: superagent}) do
    case Superagents.remove(superagent) do
      {:ok, archive} ->
        {:ok,
         gettext("Superagent removed; profile/state archived in %{archive}.", archive: archive)}

      {:error, reason} ->
        {:error, gettext("Could not remove: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:sync_agent_runtimes, %{targets: targets}), do: RuntimeSync.start(targets)

  defp execute(:start_superagent, %{superagent: superagent}) do
    case Superagents.start(superagent) do
      {:ok, _} ->
        {:ok, gettext("Superagent started. The status updates on the next read.")}

      {:error, reason} ->
        {:error, gettext("Could not start: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:stop_superagent, %{superagent: superagent}) do
    case Superagents.stop(superagent) do
      {:ok, _} -> {:ok, gettext("Superagent stopped.")}
      {:error, reason} -> {:error, gettext("Could not stop: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:pause_superagent, %{superagent: superagent}) do
    case Superagents.pause(superagent, true) do
      {:ok, _} ->
        {:ok, gettext("Superagent paused.")}

      {:error, reason} ->
        {:error, gettext("Could not pause: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:resume_superagent, %{superagent: superagent}) do
    case Superagents.pause(superagent, false) do
      {:ok, _} ->
        {:ok, gettext("Superagent resumed.")}

      {:error, reason} ->
        {:error, gettext("Could not resume: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:scale_superagent, %{superagent: superagent, workers: workers}) do
    case Superagents.scale(superagent, workers) do
      {:ok, _} ->
        {:ok, gettext("Session limit updated.")}

      {:error, reason} ->
        {:error, gettext("Could not change the limit: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:apply_agent_policy, %{superagent: superagent} = params) do
    case Policy.apply(superagent, Map.get(params, :keep, [])) do
      {:ok, _revision} ->
        {:ok, gettext("Applied. The agent's next task already follows it.")}

      {:error, :conflict} ->
        {:error,
         gettext(
           "The agent's instructions changed while you were looking. Nothing was applied: check again below."
         )}

      {:error, reason} ->
        {:error, gettext("Not applied: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:set_agent_folder_days, %{superagent: superagent, days: days}) do
    case Leftovers.put_days(superagent, days) do
      :ok when days == :never ->
        {:ok, gettext("Saved. The board no longer removes this project's folders by itself.")}

      :ok ->
        {:ok,
         ngettext(
           "Saved. Folders of tickets that ended more than %{count} day ago go on the next daily pass.",
           "Saved. Folders of tickets that ended more than %{count} days ago go on the next daily pass.",
           days
         )}

      {:error, reason} ->
        {:error, gettext("Not saved: %{reason}", reason: describe(reason))}
    end
  end

  defp execute(:sweep_agent_folders, %{superagent: superagent, days: days}),
    do: cleaned(Leftovers.clean(superagent, {:older_than, days}))

  defp execute(:clean_agent_leftovers, %{superagent: superagent}),
    do: cleaned(Leftovers.clean(superagent, :all))

  defp execute(:grant_agent_access, %{superagent: superagent, login: login} = params) do
    case AgentAccess.grant(superagent, login, Map.get(params, :rerun, [])) do
      {:ok, result} ->
        {:ok, granted_text(superagent, result)}

      {:error, reason} ->
        {:error,
         gettext("Could not allow @%{login}: %{reason}",
           login: login,
           reason: access_failure(reason)
         )}
    end
  end

  defp execute(:revoke_agent_access, %{superagent: superagent, login: login}) do
    case AgentAccess.revoke(superagent, login) do
      {:ok, login} ->
        {:ok,
         gettext("@%{login} was removed from the list of %{project}.",
           login: login,
           project: result_project(superagent)
         )}

      {:error, reason} ->
        {:error,
         gettext("Could not revoke @%{login}: %{reason}",
           login: login,
           reason: access_failure(reason)
         )}
    end
  end

  defp execute(:dismiss_access_request, %{superagent: superagent, login: login}) do
    case AgentAccess.dismiss(superagent, login) do
      {:ok, _dismissal} ->
        {:ok, gettext("Request from @%{login} set aside.", login: login)}

      {:error, reason} ->
        {:error, gettext("Could not set aside: %{reason}", reason: access_failure(reason))}
    end
  end

  defp execute(:start_agent, params), do: AgentControl.start_agent(Map.get(params, :opts, []))

  defp execute(:set_max_workers, %{max: max} = params),
    do: Orchestrator.set_max_workers(orchestrator(params), max)

  defp execute(:add_repository, %{owner: owner, name: name}),
    do: Board.add_repository(owner, name)

  defp execute(:change_setting, %{setting: "voice", value: {id, name}}),
    do: ElevenLabs.save_voice(id, name)

  defp execute(:change_setting, %{setting: "voice_name", value: name}),
    do: Settings.put("elevenlabs_voice_name", name)

  defp execute(:change_setting, %{setting: "tts_model", value: model}),
    do: Settings.put("elevenlabs_tts_model", model)

  defp execute(:change_setting, %{setting: "daily_summary", value: form}),
    do: DailySummary.put_settings(form)

  defp execute(:change_setting, %{setting: "alert_" <> kind, value: on?}),
    do: Voice.put_alert_kind(kind, on?)

  # The dispatch switches and limits are board-wide settings, written through
  # the same action as the voice ones.
  defp execute(:change_setting, %{setting: setting, value: value})
       when setting in ~w(dispatch_paused dispatch_monthly_usd dispatch_task_usd
                          dispatch_codex_timeout_minutes dispatch_reserve_percent
                          dispatch_claude_model dispatch_codex_model),
       do: Settings.put(setting, value)

  defp execute(:change_setting, %{setting: setting, value: value}) do
    case Map.fetch(@settings, setting) do
      {:ok, {module, fun}} -> apply(module, fun, [value])
      :error -> {:error, :unknown_setting}
    end
  end

  defp execute(:dismiss_summary, %{id: id}), do: DailySummary.dismiss(id)
  defp execute(:forget_conversation, _params), do: Conversation.clear()

  defp execute(:check_setup, _params) do
    rows = Setup.verify()
    {key, receipt} = Setup.Validation.receipt(rows)

    with :ok <- Settings.put(key, receipt) do
      {:ok, {rows, Setup.Validation.history()}}
    end
  end

  defp execute(:sync_now, _params), do: Oban.insert(Worker.new(%{}))
  defp execute(:update_board, _params), do: updater().pull()

  defp execute(:restart_board, _params) do
    updater().restart()
    # The stop is replaceable so a test never ends its own VM.
    Application.get_env(:agent_board, :board_stopper, &System.stop/0).()
    :ok
  end

  # A request for a named executor carries the router line the door showed
  # (or the one this door builds now). A request without an executor is
  # opened as given, with no label and no line, as before.
  defp route_requests(repo, requests) do
    signals =
      if Enum.any?(requests, &needs_route?/1), do: Routing.Signals.read_for(repo), else: nil

    Enum.map(requests, &route_request(repo, &1, signals))
  end

  defp needs_route?(%{routing: %{}}), do: false
  defp needs_route?(%{executor: executor}) when is_binary(executor), do: true
  defp needs_route?(_request), do: false

  defp route_request(_repo, %{routing: %{}} = request, _signals), do: request

  defp route_request(repo, %{executor: executor} = request, signals)
       when is_binary(executor) and is_map(signals) do
    Routing.plan(
      repo,
      request,
      Map.get(request, :requested, executor),
      Map.get(request, :decided_by, "api"),
      signals
    )
  end

  defp route_request(_repo, request, _signals), do: request

  defp github(params), do: Map.get_lazy(params, :client, &AgentBoard.GitHub.client/0)
  defp orchestrator(params), do: Map.get_lazy(params, :client, &Orchestrator.client/0)
  defp updater, do: Application.get_env(:agent_board, :updater, AgentBoard.System.Updater)

  # ---- the record ---------------------------------------------------------------

  # `what`: the decision, and its evidence, phrase, words and detail.
  defp insert!(name, spec, params, actor, what) do
    words = what[:words]

    %Decision{}
    |> Decision.changeset(%{
      action: Atom.to_string(name),
      risk: Atom.to_string(spec.risk),
      decision: what.decision,
      by: actor.by,
      via: Atom.to_string(actor.via),
      evidence: what[:evidence],
      phrase: what[:phrase],
      words: words && String.slice(words, 0, 500),
      subject: name |> subject(params) |> clip_subject(),
      repository_id: repository_id(params),
      detail: what[:detail]
    })
    |> Repo.insert!()
  end

  defp finish(row, outcome, detail) do
    row
    |> Ecto.Changeset.change(outcome: outcome, detail: detail && String.slice(detail, 0, 500))
    |> Repo.update!()
  end

  defp finish_create_tasks(repo, requests, params, client) do
    results = Board.Requests.create_requests(repo, requests, client)

    SplitGraph.record(results)
    maybe_objective(repo, params[:objective], results, client)
    {:ok, results}
  end

  # The files come first: an issue that promises a mock it does not have
  # would send the agent to work without it.
  defp with_attachments(repo, requests, files, client) do
    case Attachments.store(repo, files, client) do
      {:ok, stored} ->
        {:ok, Enum.map(requests, &attach(&1, stored, repo))}

      {:error, exception} ->
        Board.log_event(repo.id, "attachment_error", repo.name, %{
          "reason" => Exception.message(exception)
        })

        {:error, Enum.map(requests, &{&1, {:error, :attachments_failed}})}
    end
  end

  # The private folder is written before any issue names it; what it holds
  # never leaves this machine and never reaches an event.
  defp with_private(_repo, requests, nil), do: {:ok, requests}

  defp with_private(repo, requests, %{dir: dir} = private) do
    case PrivateContext.store(repo, dir, private) do
      :ok ->
        path = PrivateContext.shared_path(repo, dir)

        {:ok,
         Enum.map(requests, fn request ->
           %{
             request
             | body: IssueBody.with_private(request.body, dir, path, Map.get(request, :language))
           }
         end)}

      {:error, reason} ->
        Board.log_event(repo.id, "private_context_error", repo.name, %{
          "reason" => to_string(reason)
        })

        {:error, Enum.map(requests, &{&1, {:error, :private_failed}})}
    end
  end

  defp attach(request, stored, repo) do
    %{
      request
      | body: IssueBody.with_attachments(request.body, stored, repo, Map.get(request, :language))
    }
  end

  defp maybe_objective(repo, %{title: title} = attrs, results, client) do
    task_ids =
      for {_request, {:ok, %Task{id: id}, _outcome}} <- results, is_integer(id), do: id

    case Board.create_objective(repo, attrs, task_ids) do
      {:ok, objective} ->
        SplitGraph.publish(repo, objective, results, client)

      {:error, :not_a_group} ->
        :ok

      {:error, reason} ->
        Board.log_event(repo.id, "objective_error", title, %{"reason" => inspect(reason)})
    end
  end

  defp maybe_objective(_repo, _objective, _results, _client), do: :ok

  defp outcome(:create_tasks, {:ok, results}) do
    case Enum.count(results, &match?({_request, {:error, _}}, &1)) do
      0 -> {"ok", nil}
      failed -> {"error", "#{failed} de #{length(results)} não entraram"}
    end
  end

  defp outcome(_name, :ok), do: {"ok", nil}
  defp outcome(_name, {:ok, _}), do: {"ok", nil}
  defp outcome(_name, {:ok, _, _}), do: {"ok", nil}
  defp outcome(_name, {:error, reason}), do: {"error", describe(reason)}
  defp outcome(_name, other), do: {"error", describe(other)}

  defp dispatch_error(:paused), do: gettext("Dispatch is paused")

  defp dispatch_error(:already_running),
    do: gettext("This task already has an execution in progress")

  defp dispatch_error(:monthly_budget),
    do: gettext("This month's spend has reached the Claude Code ceiling")

  defp dispatch_error(:budget_unknown),
    do: gettext("This month's spend has a model without a price; the ceiling cannot be checked")

  defp dispatch_error(:quota_reserved),
    do: gettext("The weekly Codex quota is within the owner's reserve")

  defp dispatch_error(:task_closed), do: gettext("The task has already ended or is stopped")

  defp dispatch_error(:executor_mismatch),
    do:
      gettext(
        "The task belongs to another executor; choose the executor on the task before dispatching"
      )

  defp dispatch_error(:runner_missing),
    do:
      gettext(
        "The executor binary does not exist or is not executable on this Mac; check the path in Settings"
      )

  defp dispatch_error(:repo_missing),
    do: gettext("The local checkout of the repository does not exist")

  defp dispatch_error(:no_repository), do: gettext("The task has no repository")
  defp dispatch_error(reason), do: describe(reason)

  defp executor_name(executor), do: Executors.name(executor)

  defp cleaned({:ok, result}), do: {:ok, cleaned_text(result)}

  defp cleaned({:error, {:partial, result, detail}}),
    do:
      {:error,
       gettext("It stopped halfway. %{done} %{detail}",
         done: cleaned_text(result),
         detail: detail || ""
       )}

  defp cleaned({:error, :unavailable}),
    do: {:error, gettext("This board has no access to the agent's folders.")}

  defp cleaned({:error, reason}),
    do: {:error, gettext("Nothing was removed: %{reason}", reason: describe(reason))}

  defp cleaned_text(%{folders: folders, prs: prs, kept: kept, failed: failed}) do
    [
      ngettext("%{count} folder removed", "%{count} folders removed", folders),
      prs > 0 && ngettext("%{count} pull request closed", "%{count} pull requests closed", prs),
      kept > 0 &&
        ngettext(
          "%{count} kept (open ticket or uncommitted changes)",
          "%{count} kept (open ticket or uncommitted changes)",
          kept
        ),
      failed > 0 && ngettext("%{count} failed", "%{count} failed", failed)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
    |> Kernel.<>(".")
  end

  defp project(%AgentBoard.Superagents.Superagent{repository: %Repository{} = repo}),
    do: "#{repo.owner}/#{repo.name}"

  defp project(%AgentBoard.Superagents.Superagent{} = superagent),
    do: "projeto #{superagent.repository_id}"

  # The project in a result. `project/1` stays as it is: `phrase/3` uses it,
  # and the gate rebuilds the sentence in a process with another locale.
  defp result_project(%AgentBoard.Superagents.Superagent{repository: %Repository{}} = superagent),
    do: project(superagent)

  defp result_project(%AgentBoard.Superagents.Superagent{} = superagent),
    do: gettext("project %{id}", id: superagent.repository_id)

  defp rerun_text(%{rerun: [_ | _] = rerun}, "en-US"),
    do: " The refused mentions on #{issue_list(rerun)} run again."

  defp rerun_text(%{rerun: [_ | _] = rerun}, _lang),
    do: " As menções recusadas em #{issue_list(rerun)} rodam de novo."

  defp rerun_text(_params, _lang), do: ""

  defp issue_list(rerun), do: Enum.map_join(rerun, ", ", &"##{&1.number}")

  defp granted_text(superagent, %{login: login, requeued: requeued, failed: failed}) do
    gettext("@%{login} allowed on %{project}.",
      login: login,
      project: result_project(superagent)
    ) <>
      if(requeued == [],
        do: "",
        else: " " <> gettext("Running again: %{numbers}.", numbers: numbers(requeued))
      ) <>
      if(failed == [],
        do: "",
        else:
          " " <>
            gettext("Could not reprocess %{numbers}: ask for a new mention.",
              numbers: numbers(failed)
            )
      )
  end

  defp numbers(numbers), do: Enum.map_join(numbers, ", ", &"##{&1}")

  # These follow a colon ("Could not allow @login: ..."), so they start small.
  defp access_failure(:conflict),
    do: gettext("the list changed in the agent's panel; check and try again.")

  defp access_failure(:invalid_login), do: gettext("that GitHub login is not valid.")

  defp access_failure(:owner_protected),
    do: gettext("the repository owner cannot be revoked.")

  defp access_failure(:github_source_missing),
    do: gettext("this project's agent does not have GitHub configured.")

  defp access_failure(%{__exception__: true}),
    do: gettext("the agent did not answer; is it running?")

  defp access_failure(:timeout), do: gettext("the agent took too long to answer.")

  defp access_failure({:http, status}),
    do: gettext("the agent answered with an error (HTTP %{status}).", status: status)

  defp access_failure(:malformed),
    do: gettext("the agent gave an answer the board does not understand.")

  defp access_failure(other) do
    Logger.warning("agent access failed: #{inspect(other)}")
    gettext("the agent refused the request.")
  end

  defp describe({:setup, text}) when is_binary(text), do: text

  defp describe(:dsh_missing),
    do:
      gettext(
        "the dsh command of DeepSeek Harness is not on this machine. Install the Harness and its command, then try again."
      )

  defp describe(:ps_missing),
    do:
      gettext(
        "The agent needs a full ps command to start. Install procps (procps-ng on Alpine), then review the installation again."
      )

  defp describe(:bot_missing),
    do:
      gettext(
        "the agent has no GitHub sign-in on this machine yet. AI and setup shows the command that signs it in."
      )

  defp describe({:prototype_in_the_way, path}),
    do:
      gettext(
        "the folder %{path} exists but is not the agent's code. Move it away and try again.",
        path: path
      )

  defp describe({:command, tool, output}),
    do: gettext("%{tool} failed: %{output}", tool: tool, output: output)

  defp describe(:profile_not_created),
    do: gettext("dsh did not create the agent's profile.")

  defp describe({:already_installed, profile}),
    do:
      gettext(
        "this machine already has an agent installed for this repository (%{profile}); add it to the board in Projects instead.",
        profile: profile
      )

  defp describe(:provision_failed),
    do: gettext("this project's setup did not finish; use Try again.")

  defp describe(:nothing_to_retry), do: gettext("this project has no provisioning to redo.")

  defp describe(%{__exception__: true} = exception), do: Exception.message(exception)
  defp describe(text) when is_binary(text), do: text
  defp describe(%Ecto.Changeset{errors: errors}), do: inspect(errors)
  defp describe(other), do: inspect(other)

  # The record of a refusal has to fit whatever was refused.
  defp clip_subject(nil), do: nil
  defp clip_subject(subject), do: String.slice(subject, 0, 255)

  defp subject(_name, %{
         superagent: %AgentBoard.Superagents.Superagent{profile: profile},
         login: login
       }),
       do: "#{profile} @#{login}"

  defp subject(_name, %{superagent: %AgentBoard.Superagents.Superagent{profile: profile}}),
    do: profile

  defp subject(:provision_superagent, %{repository: repo}), do: "#{repo.owner}/#{repo.name}"
  defp subject(:adopt_superagent, %{profile: profile}), do: profile

  defp subject(:install_first_superagent, %{repository: repo}),
    do: "#{repo.owner}/#{repo.name}"

  defp subject(:create_tasks, %{repository: repo, requests: requests}),
    do: "#{repo.owner}/#{repo.name} (#{length(requests)})"

  defp subject(_name, %{task: %Task{number: n}}), do: "##{n}"

  defp subject(_name, %{ticket_id: id} = params),
    do: "ticket #{id}" <> if(params[:number], do: " ##{params.number}", else: "")

  defp subject(:set_max_workers, %{max: max}), do: "maxWorkers=#{max}"
  defp subject(:add_repository, %{owner: owner, name: name}), do: "#{owner}/#{name}"
  defp subject(:change_setting, %{setting: setting}), do: setting
  defp subject(:dismiss_summary, %{id: id}), do: "daily_summary #{id}"
  defp subject(_name, _params), do: nil

  defp repository_id(%{superagent: %AgentBoard.Superagents.Superagent{repository_id: id}}), do: id
  defp repository_id(%{repository: %Repository{id: id}}), do: id
  defp repository_id(%{task: %Task{repository_id: id}}), do: id
  defp repository_id(%{repository_id: id}) when is_integer(id), do: id
  defp repository_id(_params), do: nil

  defp log(name, decision, actor_or_row, detail) do
    Logger.info(
      "action #{name} decision=#{decision} by=#{actor_or_row.by} via=#{actor_or_row.via} " <>
        "result=#{detail}"
    )
  end

  # ---- helpers ------------------------------------------------------------------

  defp q(text), do: "“" <> String.trim(to_string(text)) <> "”"

  # A question that already ends in its own mark is not asked twice ("?”?").
  defp ask_mark(question) do
    if String.ends_with?(String.trim(to_string(question)), ["?", "!", "."]), do: "", else: "?"
  end

  # The voice's short title; a cut one says so, so a sentence never reads
  # as if the title ended there.
  defp short(title) do
    full = (title || "") |> String.trim() |> String.trim_trailing(".")
    cut = Phrases.short_title(full)
    if cut == full, do: cut, else: cut <> "…"
  end

  defp title(%{title: title}), do: short(title)

  defp titles(requests, conjunction) do
    quoted = Enum.map(requests, &q(title(&1)))
    {init, [last]} = Enum.split(quoted, -1)
    Enum.join(init, ", ") <> " #{conjunction} " <> last
  end

  defp repo_name(%Repository{name: name}), do: name

  # Who the issues are for (`AgentBoard.Executors`): the DeepSeek runner
  # starts on its own (the mention); Claude Code and Codex only get a label.
  defp executor_of(requests) do
    case requests |> Enum.map(&Map.get(&1, :executor)) |> Enum.uniq() do
      [executor] when executor not in [nil, "dsh"] -> executor
      _ -> nil
    end
  end

  defp for_whom(nil, _lang), do: ""
  defp for_whom(executor, "en-US"), do: " for #{Executors.name(executor)}"
  defp for_whom(executor, _lang), do: " para o #{Executors.name(executor)}"

  defp create_phrase(repo, requests, lang) do
    case {lang, requests, executor_of(requests)} do
      {"en-US", [one], executor} ->
        "Create the task #{q(title(one))} in #{repo_name(repo)}#{for_whom(executor, lang)}? " <>
          after_create(executor, 1, lang)

      {"en-US", _many, executor} ->
        "Create #{length(requests)} tasks in #{repo_name(repo)}#{for_whom(executor, lang)}: " <>
          "#{titles(requests, "and")}? " <> after_create(executor, length(requests), lang)

      {_pt, [one], executor} ->
        "Criar no #{repo_name(repo)} a tarefa #{q(title(one))}#{for_whom(executor, lang)}? " <>
          after_create(executor, 1, lang)

      {_pt, _many, executor} ->
        "Criar no #{repo_name(repo)} #{length(requests)} tarefas#{for_whom(executor, lang)}: " <>
          "#{titles(requests, "e")}? " <> after_create(executor, length(requests), lang)
    end
  end

  defp held_note(requests, lang) do
    held? =
      Enum.any?(requests, fn request ->
        Map.get(request, :depends_on, []) != [] and Map.get(request, :executor) in [nil, "dsh"]
      end)

    case {held?, lang} do
      {false, _lang} ->
        ""

      {true, "en-US"} ->
        " Those that depend on others wait: the board calls the agent once they merge."

      {true, _lang} ->
        " As que dependem de outras esperam: o board chama o agente quando forem mescladas."
    end
  end

  defp after_create(nil, 1, "en-US"),
    do: "The board opens the GitHub issue and the agent starts on its own."

  defp after_create(nil, _n, "en-US"),
    do: "The board opens the GitHub issues and the agent starts on its own."

  defp after_create(nil, 1, _lang),
    do: "O board abre a issue no GitHub e o agente começa sozinho."

  defp after_create(nil, _n, _lang),
    do: "O board abre as issues no GitHub e o agente começa sozinho."

  defp after_create(executor, _n, "en-US"),
    do: "The board opens it labelled #{Executors.label(executor)}; nothing starts on its own."

  defp after_create(executor, _n, _lang),
    do: "O board abre com o rótulo #{Executors.label(executor)}; nada começa sozinho."

  defp setting_value({id, _name}), do: id
  defp setting_value(%{} = form), do: form |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  defp setting_value(value), do: to_string(value)

  defp present(""), do: nil
  defp present(confirm), do: confirm

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/u, " ")
  end
end
