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

  require Logger
  import Ecto.Query, warn: false

  alias AgentBoard.Actions.Decision

  alias AgentBoard.{
    AgentAccess,
    AgentControl,
    Board,
    Conversation,
    DailySummary,
    ElevenLabs,
    Executors,
    Orchestrator,
    Repo,
    Routing,
    Runners,
    Settings,
    Superagents,
    Voice
  }

  alias AgentBoard.Board.{Attachments, Repository, SplitGraph, Task}
  alias AgentBoard.Intake.IssueBody
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
    :stop_task,
    :undo_created_task,
    :archive_task,
    :resume_task,
    :retry_ticket,
    :auto_retry_ticket,
    :dispatch_task,
    :stop_execution,
    :provision_superagent,
    :remove_superagent,
    :start_superagent,
    :stop_superagent,
    :pause_superagent,
    :resume_superagent,
    :scale_superagent,
    :grant_agent_access,
    :revoke_agent_access,
    :dismiss_access_request,
    :start_agent,
    :set_max_workers,
    :add_repository,
    :change_setting,
    :dismiss_summary,
    :forget_conversation,
    :sync_now,
    :update_board,
    :restart_board
  ]

  @settings %{
    "language" => {Voice, :put_language},
    "volume" => {Voice, :put_volume},
    "speed" => {Voice, :put_speed},
    "style" => {Voice, :put_style},
    "pause" => {Voice, :put_pause},
    "earcons" => {Voice, :put_earcons},
    "input" => {Voice, :put_input},
    "engine" => {Voice, :put_engine},
    "replies" => {Voice, :put_replies},
    "narrate" => {Voice, :put_narrate},
    "attention" => {Voice, :put_attention}
  }

  @max_retries 3

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

  defp spec(:dispatch_task),
    do: %{
      risk: :red,
      does: "inicia o Claude Code ou o Codex num worktree e gasta a assinatura do dono"
    }

  defp spec(:stop_execution),
    do: %{risk: :red, does: "encerra o processo de uma execução local e deixa a tarefa bloqueada"}

  defp spec(:provision_superagent),
    do: %{risk: :red, does: "cria profile, porta, state e setup de um superagent novo"}

  defp spec(:remove_superagent),
    do: %{risk: :red, does: "para o superagent e arquiva profile/state; o projeto sai do board"}

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

  def phrase(:create_tasks, %{repository: repo, requests: requests}, lang) do
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

  def phrase(:ask_task, %{task: task, question: question}, "en-US"),
    do:
      "Ask the agent on task ##{task.number}: #{q(question)}#{ask_mark(question)} " <>
        "The board comments on the GitHub issue."

  def phrase(:ask_task, %{task: task, question: question}, _lang),
    do:
      "Perguntar ao agente na tarefa ##{task.number}: #{q(question)}#{ask_mark(question)} " <>
        "O board comenta na issue do GitHub."

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

  def phrase(:provision_superagent, %{repository: repo, source: source, path: path}, "en-US"),
    do:
      "Provision DeepSeek for #{repo_name(repo)} from #{source.profile}? The board creates " <>
        "a profile, port and state, and uses the checkout #{short(path)}."

  def phrase(:provision_superagent, %{repository: repo, source: source, path: path}, _lang),
    do:
      "Provisionar o DeepSeek para #{repo_name(repo)} a partir de #{source.profile}? O board " <>
        "cria profile, porta e state, e usa o checkout #{short(path)}."

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

  def phrase(:resume_task, %{task: task}, _lang),
    do:
      "Retomar a tarefa ##{task.number}, #{q(short(task.title))}? Ela volta para a fila do quadro."

  def phrase(:retry_ticket, params, _lang) do
    target = if params[:number], do: "de ##{params.number}", else: "do ticket"

    "Pedir ao agente uma nova tentativa #{target} agora? " <>
      "Ele abre uma rodada nova no ticket e gasta tokens do executor."
  end

  def phrase(:auto_retry_ticket, %{ticket_id: id} = params, _lang),
    do:
      "Nova tentativa automática do ticket #{id} (#{params[:attempt] || "?"} de #{@max_retries}) " <>
        "depois de uma falha de rede ou do provedor."

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
  `{:words, utterance}`) and `language:` (of that phrase).
  """
  @spec run(name(), map(), actor(), keyword()) :: term() | {:error, refusal()}
  def run(name, params, %{by: _, via: _} = actor, opts \\ []) when is_map(params) do
    spec = spec(name)
    lang = Keyword.get(opts, :language, "pt-BR")
    phrase = phrase(name, params, lang)

    case gate(name, spec, actor, present(Keyword.get(opts, :confirm)), phrase) do
      {:go, decision, evidence, words} ->
        row =
          insert!(name, spec, params, actor, %{
            decision: decision,
            evidence: evidence,
            phrase: phrase,
            words: words
          })

        execute_recorded(name, params, row)

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

  defp execute_recorded(name, params, row) do
    result = execute(name, params)
    {outcome, detail} = outcome(name, result)
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
    with_files = with_attachments(repo, requests, Map.get(params, :attachments, []), client)

    case with_files do
      {:ok, ready} -> finish_create_tasks(repo, ready, params, client)
      {:error, results} -> {:ok, results}
    end
  end

  defp execute(:ask_task, %{task: task, question: question} = params),
    do: Board.ask(task, question, github(params))

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
         "Despacho iniciado no #{Executors.name(executor)} " <>
           "(sessão #{execution.session_id || execution.id}). O progresso aparece em Execuções."}

      {:error, reason} ->
        {:error, dispatch_error(reason)}
    end
  end

  defp execute(:stop_execution, %{execution: execution}) do
    case Runners.stop(execution) do
      {:ok, _execution} ->
        {:ok, "Execução parada. A tarefa ficou bloqueada para você decidir."}

      {:error, :already_finished} ->
        {:error, "A execução já terminou; veja o resultado em Execuções."}

      {:error, :not_running} ->
        {:error, "Essa execução não está mais ativa."}

      {:error, reason} ->
        {:error, "Não foi possível parar a execução: #{describe(reason)}"}
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
         "Superagent #{superagent.profile} reservado na porta #{superagent.port}; o status atualiza no ticker."}

      {:error, reason} ->
        {:error, "Não foi possível provisionar: #{describe(reason)}"}
    end
  end

  defp execute(:remove_superagent, %{superagent: superagent}) do
    case Superagents.remove(superagent) do
      {:ok, archive} -> {:ok, "Superagent removido; profile/state arquivados em #{archive}."}
      {:error, reason} -> {:error, "Não foi possível remover: #{describe(reason)}"}
    end
  end

  defp execute(:start_superagent, %{superagent: superagent}) do
    case Superagents.start(superagent) do
      {:ok, _} -> {:ok, "Superagent iniciado. O status atualiza na próxima leitura."}
      {:error, reason} -> {:error, "Não foi possível iniciar: #{describe(reason)}"}
    end
  end

  defp execute(:stop_superagent, %{superagent: superagent}) do
    case Superagents.stop(superagent) do
      {:ok, _} -> {:ok, "Superagent parado."}
      {:error, reason} -> {:error, "Não foi possível parar: #{describe(reason)}"}
    end
  end

  defp execute(:pause_superagent, %{superagent: superagent}) do
    case Superagents.pause(superagent, true) do
      {:ok, _} -> {:ok, "Superagent pausado."}
      {:error, reason} -> {:error, "Não foi possível pausar: #{describe(reason)}"}
    end
  end

  defp execute(:resume_superagent, %{superagent: superagent}) do
    case Superagents.pause(superagent, false) do
      {:ok, _} -> {:ok, "Superagent retomado."}
      {:error, reason} -> {:error, "Não foi possível retomar: #{describe(reason)}"}
    end
  end

  defp execute(:scale_superagent, %{superagent: superagent, workers: workers}) do
    case Superagents.scale(superagent, workers) do
      {:ok, _} -> {:ok, "Limite de sessões atualizado."}
      {:error, reason} -> {:error, "Não foi possível mudar o limite: #{describe(reason)}"}
    end
  end

  defp execute(:grant_agent_access, %{superagent: superagent, login: login} = params) do
    case AgentAccess.grant(superagent, login, Map.get(params, :rerun, [])) do
      {:ok, result} ->
        {:ok, granted_text(superagent, result)}

      {:error, reason} ->
        {:error, "Não foi possível liberar @#{login}: #{access_failure(reason)}"}
    end
  end

  defp execute(:revoke_agent_access, %{superagent: superagent, login: login}) do
    case AgentAccess.revoke(superagent, login) do
      {:ok, login} ->
        {:ok, "@#{login} saiu da lista de #{project(superagent)}."}

      {:error, reason} ->
        {:error, "Não foi possível revogar @#{login}: #{access_failure(reason)}"}
    end
  end

  defp execute(:dismiss_access_request, %{superagent: superagent, login: login}) do
    case AgentAccess.dismiss(superagent, login) do
      {:ok, _dismissal} -> {:ok, "Pedido de @#{login} dispensado."}
      {:error, reason} -> {:error, "Não foi possível dispensar: #{access_failure(reason)}"}
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

  # The dispatch switches and limits are board-wide settings, written through
  # the same action as the voice ones.
  defp execute(:change_setting, %{setting: setting, value: value})
       when setting in ~w(dispatch_paused dispatch_monthly_usd dispatch_task_usd
                          dispatch_codex_timeout_minutes dispatch_reserve_percent
                          dispatch_claude_model dispatch_codex_model dsh_repositories),
       do: Settings.put(setting, value)

  defp execute(:change_setting, %{setting: setting, value: value}) do
    case Map.fetch(@settings, setting) do
      {:ok, {module, fun}} -> apply(module, fun, [value])
      :error -> {:error, :unknown_setting}
    end
  end

  defp execute(:dismiss_summary, %{id: id}), do: DailySummary.dismiss(id)
  defp execute(:forget_conversation, _params), do: Conversation.clear()
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
    signals = if Enum.any?(requests, &needs_route?/1), do: Routing.Signals.read(), else: nil
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

  defp dispatch_error(:paused), do: "o despacho está pausado"
  defp dispatch_error(:already_running), do: "esta tarefa já tem uma execução em andamento"

  defp dispatch_error(:monthly_budget),
    do: "o gasto do mês já chegou ao teto do Claude Code"

  defp dispatch_error(:budget_unknown),
    do: "o gasto do mês tem um modelo sem preço; o teto não pode ser conferido"

  defp dispatch_error(:quota_reserved),
    do: "a cota semanal do Codex está dentro da reserva do dono"

  defp dispatch_error(:task_closed), do: "a tarefa já terminou ou está parada"

  defp dispatch_error(:executor_mismatch),
    do: "a tarefa é de outro executor; escolha o executor na tarefa antes de despachar"

  defp dispatch_error(:runner_missing),
    do:
      "o binário do executor não existe ou não é executável neste Mac; confira o caminho em Configurações"

  defp dispatch_error(:repo_missing), do: "o checkout local do repositório não existe"
  defp dispatch_error(:no_repository), do: "a tarefa não tem repositório"
  defp dispatch_error(reason), do: describe(reason)

  defp executor_name(executor), do: Executors.name(executor)

  defp project(%AgentBoard.Superagents.Superagent{repository: %Repository{} = repo}),
    do: "#{repo.owner}/#{repo.name}"

  defp project(%AgentBoard.Superagents.Superagent{} = superagent),
    do: "projeto #{superagent.repository_id}"

  defp rerun_text(%{rerun: [_ | _] = rerun}, "en-US"),
    do: " The refused mentions on #{issue_list(rerun)} run again."

  defp rerun_text(%{rerun: [_ | _] = rerun}, _lang),
    do: " As menções recusadas em #{issue_list(rerun)} rodam de novo."

  defp rerun_text(_params, _lang), do: ""

  defp issue_list(rerun), do: Enum.map_join(rerun, ", ", &"##{&1.number}")

  defp granted_text(superagent, %{login: login, requeued: requeued, failed: failed}) do
    "@#{login} liberado em #{project(superagent)}." <>
      if(requeued == [], do: "", else: " Rodando de novo: #{numbers(requeued)}.") <>
      if(failed == [],
        do: "",
        else: " Não consegui reprocessar #{numbers(failed)}: peça uma nova menção."
      )
  end

  defp numbers(numbers), do: Enum.map_join(numbers, ", ", &"##{&1}")

  defp access_failure(:conflict),
    do: "a lista mudou no painel do agente; confira e tente de novo."

  defp access_failure(:invalid_login), do: "esse login do GitHub não é válido."
  defp access_failure(:owner_protected), do: "o dono do repositório não pode ser revogado."

  defp access_failure(:github_source_missing),
    do: "o agente deste projeto não tem o GitHub configurado."

  defp access_failure(%{__exception__: true}), do: "o agente não respondeu; ele está ligado?"
  defp access_failure(:timeout), do: "o agente demorou demais para responder."
  defp access_failure({:http, status}), do: "o agente respondeu com erro (HTTP #{status})."
  defp access_failure(:malformed), do: "o agente deu uma resposta que o board não entende."

  defp access_failure(other) do
    Logger.warning("agent access failed: #{inspect(other)}")
    "o agente recusou o pedido."
  end

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

  defp subject(:remove_superagent, %{
         superagent: %AgentBoard.Superagents.Superagent{profile: profile}
       }),
       do: profile

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
  defp repository_id(%{repository: %Repository{id: id}}), do: id
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
