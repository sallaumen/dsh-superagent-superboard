defmodule AgentBoard.Voice.Phrases do
  @moduledoc """
  Every sentence the agent speaks, per language.

  One place owns the spoken words so a language never leaks into another
  (a Portuguese voice reading "Task is now running" is the mix this module
  exists to prevent). The functions are pure: the caller passes the
  language and, for the phrase pools, a `turn` integer that rotates the
  pick, so two calls in a row never say the same sentence.
  """

  @languages [
    %{id: "pt-BR", name: "Português (Brasil)", tts: "pt"},
    %{id: "en-US", name: "English", tts: "en"}
  ]
  @default "pt-BR"
  @title_max 60

  @doc "The languages the picker offers."
  def languages, do: @languages

  @doc "The language spoken when none is saved."
  def default_language, do: @default

  @doc "Whether a language id is one of the offered languages."
  def valid_language?(id), do: Enum.any?(@languages, &(&1.id == id))

  @doc "The ISO 639-1 code the TTS engine expects (`pt`, `en`)."
  def tts_code(lang), do: Enum.find_value(@languages, "pt", &(&1.id == lang && &1.tts))

  @doc "A title short enough to say in one breath, cut at a word."
  def short_title(title) when is_binary(title) do
    title = title |> String.trim() |> String.trim_trailing(".")

    if String.length(title) <= @title_max do
      title
    else
      title
      |> String.slice(0, @title_max)
      |> String.replace(~r/\s+\S*\z/u, "")
      |> String.trim_trailing(",;:-")
    end
  end

  def short_title(_title), do: ""

  # ---- the attention calls ------------------------------------------------

  @attention %{
    "pt-BR" => %{
      question: [
        "Ei, preciso de você: tenho uma pergunta sobre %{t}.",
        "Com licença, %{t} está esperando uma resposta sua.",
        "Pode me dar uma mão? Fiquei com uma dúvida em %{t}.",
        "Tenho uma pergunta rápida sobre %{t}, quando você puder.",
        "Parei em %{t} para te perguntar uma coisa.",
        "Preciso da sua opinião em %{t} para continuar.",
        "Antes de seguir em %{t}, preciso te perguntar algo.",
        "Quando tiver um minuto, deixei uma pergunta em %{t}.",
        "Psiu, tem uma pergunta minha te esperando em %{t}.",
        "Não quero chutar: em %{t}, preciso que você decida."
      ],
      blocked: [
        "Travei em %{t} e preciso da sua ajuda.",
        "Atenção: %{t} está bloqueada.",
        "Ei, %{t} emperrou. Pode dar uma olhada?",
        "Não consigo avançar em %{t} sem você.",
        "Encontrei um bloqueio em %{t}. Deixei o motivo no quadro.",
        "Preciso de uma ajuda: %{t} parou.",
        "Uma ajudinha aqui: %{t} está bloqueada.",
        "%{t} ficou bloqueada. Quando puder, veja o motivo.",
        "Bati num obstáculo em %{t}. Pode me destravar?",
        "Parei em %{t}: tem algo que só você resolve."
      ],
      ready: [
        "Terminei %{t}. Está pronta para a sua revisão.",
        "Boa notícia: %{t} está pronta para revisar.",
        "Pode revisar %{t}? Já está pronta.",
        "%{t} está esperando a sua revisão.",
        "Acabei %{t}. Quando puder, dá uma olhada no PR.",
        "Mais uma pronta: %{t}, aguardando a sua revisão.",
        "Ei, %{t} ficou pronta. Agora é com você.",
        "Entreguei %{t}. Falta só a sua revisão.",
        "%{t} chegou na revisão. Quando quiser, é sua vez.",
        "Pronto, %{t} está pronta para revisar."
      ],
      stalled: [
        "Fiquei em silêncio em %{t} faz um tempo. Dá uma olhada?",
        "Não dou sinal em %{t} há um bom tempo. Pode conferir se travei?",
        "Parece que empaquei em %{t}: nenhum relatório nem mudança no código.",
        "Silêncio demais em %{t}. Vale checar o que está acontecendo.",
        "Ei, %{t} ficou sem sinal meu. Melhor você olhar.",
        "Faz tempo que não mexo em %{t}. Pode ver se ainda estou indo?",
        "Nada novo meu em %{t} há um bom tempo. Confere para mim?",
        "Em %{t} eu sumi: nem relatório, nem commit. Dá uma espiada.",
        "Acho que travei em %{t}. Se puder, veja o que falta.",
        "%{t} está sem sinal meu há mais tempo que o normal. Quer olhar?"
      ]
    },
    "en-US" => %{
      question: [
        "Hey, I need you: I have a question about %{t}.",
        "Excuse me, %{t} is waiting for your answer.",
        "Can you give me a hand? I have a doubt in %{t}.",
        "Quick question about %{t}, whenever you can.",
        "I stopped at %{t} to ask you something.",
        "I need your call on %{t} to keep going.",
        "Before I go on with %{t}, I need to ask you something.",
        "When you have a minute, I left a question in %{t}.",
        "Psst, a question of mine is waiting for you in %{t}.",
        "I'd rather not guess: in %{t}, I need you to decide."
      ],
      blocked: [
        "I'm stuck on %{t} and need your help.",
        "Heads up: %{t} is blocked.",
        "Hey, %{t} got stuck. Can you take a look?",
        "I can't move %{t} forward without you.",
        "I hit a block in %{t}. The reason is on the board.",
        "I need a hand: %{t} stopped.",
        "A little help here: %{t} is blocked.",
        "%{t} is blocked. When you can, check the reason.",
        "I ran into an obstacle in %{t}. Can you unblock me?",
        "I stopped at %{t}: there's something only you can solve."
      ],
      ready: [
        "I finished %{t}. It's ready for your review.",
        "Good news: %{t} is ready to review.",
        "Can you review %{t}? It's ready.",
        "%{t} is waiting for your review.",
        "Done with %{t}. When you can, take a look at the PR.",
        "One more ready: %{t}, waiting for your review.",
        "Hey, %{t} is ready. Your turn.",
        "I delivered %{t}. It only needs your review.",
        "%{t} reached review. Whenever you like, it's yours.",
        "All set, %{t} is ready to review."
      ],
      stalled: [
        "I've gone quiet on %{t} for a while. Can you take a look?",
        "No sign from me on %{t} in a good while. Could you check whether I'm stuck?",
        "Looks like I stalled on %{t}: no report and no code change.",
        "Too much silence on %{t}. Worth checking what's going on.",
        "Hey, %{t} has had no signal from me. Better have a look.",
        "I haven't touched %{t} in a while. Can you see whether I'm still moving?",
        "Nothing new from me on %{t} in a good while. Would you check?",
        "On %{t} I went dark: no report, no commit. Have a peek.",
        "I think I'm stuck on %{t}. If you can, see what's missing.",
        "%{t} has had no signal from me for longer than usual. Want to look?"
      ]
    }
  }

  @doc "The attention kinds: the states where the agent needs the owner, and the silence."
  def attention_kinds, do: [:question, :blocked, :ready, :stalled]

  @doc "The pool of attention phrases for a language and kind."
  def attention_pool(lang, kind), do: @attention |> lang_map(lang) |> Map.fetch!(kind)

  @doc "A call for the owner's attention; `turn` rotates through the pool."
  def attention(lang, kind, title, turn) do
    lang |> attention_pool(kind) |> pick(turn) |> fill(title)
  end

  # ---- the other board news -----------------------------------------------

  @moved %{
    "pt-BR" => %{
      running: ["Comecei %{t}.", "Agora estou em %{t}.", "Mãos à obra em %{t}."],
      queued: ["%{t} voltou para a fila.", "Deixei %{t} na fila por enquanto."]
    },
    "en-US" => %{
      running: ["I started %{t}.", "Now working on %{t}.", "Getting to work on %{t}."],
      queued: ["%{t} went back to the queue.", "I left %{t} in the queue for now."]
    }
  }

  @doc "A task moved into a lane that does not need the owner."
  def moved(lang, state, title, turn) do
    @moved |> lang_map(lang) |> Map.fetch!(state) |> pick(turn) |> fill(title)
  end

  @doc "The sync failed; the board shows its saved data."
  def sync_failed("en-US"), do: "The sync failed. I'm showing the saved data."
  def sync_failed(_lang), do: "A sincronização falhou. Estou mostrando os dados salvos."

  @doc "The sync finished with more errors than the last one."
  def sync_errors("en-US", 1), do: "The sync finished with 1 error."
  def sync_errors("en-US", n), do: "The sync finished with #{n} errors."
  def sync_errors(_lang, 1), do: "A sincronização terminou com 1 erro."
  def sync_errors(_lang, n), do: "A sincronização terminou com #{n} erros."

  @doc "The confirmation for an action the owner took on a task."
  def task_action("en-US", title, action) do
    t = short_title(title)

    case action do
      "stop" -> "Stopped #{t}."
      "archive" -> "Archived #{t}."
      "resume" -> "Resumed #{t}."
      "created" -> "Created #{t}."
      other -> "#{t}: #{other}."
    end
  end

  def task_action(_lang, title, action) do
    t = short_title(title)

    case action do
      "stop" -> "Parei #{t}."
      "archive" -> "Arquivei #{t}."
      "resume" -> "Retomei #{t}."
      "created" -> "Criei #{t}."
      other -> "#{t}: #{other}."
    end
  end

  @doc "The confirmation spoken when the owner switches the voice language."
  def language_switched("en-US"), do: "Done. From now on I'll speak English."
  def language_switched(_lang), do: "Pronto. A partir de agora eu falo em português."

  @doc "The phrase the voice preview speaks."
  def preview("en-US"), do: "Hi! This is how I'll sound when I talk to you."
  def preview(_lang), do: "Oi! É assim que eu vou soar quando falar com você."

  @doc "The phrase spoken after a voice is saved."
  def voice_saved("en-US"), do: "Voice selected."
  def voice_saved(_lang), do: "Voz escolhida."

  # ---- the conversation -------------------------------------------------

  @doc "The model answered with something the board cannot use."
  def not_understood("en-US"), do: "Sorry, I didn't get that. Can you say it another way?"
  def not_understood(_lang), do: "Desculpa, não entendi. Pode falar de outro jeito?"

  @doc "The model could not answer; the reason is said in words."
  def ai_failed(lang, reason) do
    case {lang, reason} do
      {"en-US", :not_configured} ->
        "The AI is not configured, so I can only take simple commands."

      {"en-US", :budget_exhausted} ->
        "Today's AI budget is used up. Try again tomorrow."

      {"en-US", :usage_limit} ->
        "The AI provider hit its usage limit. Try again in a bit."

      {"en-US", _} ->
        "I couldn't think that through right now. Try again in a moment."

      {_, :not_configured} ->
        "A IA não está configurada, então só entendo comandos simples."

      {_, :budget_exhausted} ->
        "O orçamento de IA de hoje acabou. Tenta de novo amanhã."

      {_, :usage_limit} ->
        "O provedor de IA atingiu o limite de uso. Tenta daqui a pouco."

      {_, _} ->
        "Não consegui pensar nisso agora. Tenta de novo em um instante."
    end
  end

  @doc "Asked for new work without a project to put it in."
  def which_project("en-US"), do: "Sure. Which project should this task go to?"
  def which_project(_lang), do: "Claro. Em qual projeto eu coloco essa tarefa?"

  @doc "The request needs one answer before it can become a task."
  def clarify("en-US", question), do: "Before I create it, one question: #{question}"
  def clarify(_lang, question), do: "Antes de criar, uma dúvida: #{question}"

  @doc "The refined task, waiting for a spoken yes."
  def propose_task("en-US", repo, title),
    do: "Got it. I'll create in #{repo_name(repo)}: #{short_title(title)}. Shall I?"

  def propose_task(_lang, repo, title),
    do: "Entendi. Vou criar no #{repo_name(repo)} a tarefa: #{short_title(title)}. Posso criar?"

  @doc "A stop or archive, waiting for a spoken yes."
  def propose_task_action("en-US", "stop_task", n, t),
    do: "Stop task #{n}, #{short_title(t)}? Shall I?"

  def propose_task_action("en-US", _kind, n, t),
    do: "Archive task #{n}, #{short_title(t)}? Shall I?"

  def propose_task_action(_lang, "stop_task", n, t),
    do: "Parar a tarefa #{n}, #{short_title(t)}? Posso?"

  def propose_task_action(_lang, _kind, n, t),
    do: "Arquivar a tarefa #{n}, #{short_title(t)}? Posso?"

  def task_created("en-US", n, repo), do: "Done. Task #{n} is in the #{repo_name(repo)} queue."

  def task_created(_lang, n, repo),
    do: "Pronto. A tarefa #{n} entrou na fila do #{repo_name(repo)}."

  def task_existing("en-US", n), do: "That one was already in the queue, as task #{n}."
  def task_existing(_lang, n), do: "Essa já estava na fila, como tarefa #{n}."

  def task_failed("en-US"), do: "I couldn't create the task. Check the activity and try again."

  def task_failed(_lang),
    do: "Não consegui criar a tarefa. Dá uma olhada na atividade e tenta de novo."

  def task_action_done("en-US", "stop_task", n), do: "Stopped task #{n}."
  def task_action_done("en-US", _kind, n), do: "Archived task #{n}."
  def task_action_done(_lang, "stop_task", n), do: "Parei a tarefa #{n}."
  def task_action_done(_lang, _kind, n), do: "Arquivei a tarefa #{n}."

  def task_action_failed("en-US", _kind, n),
    do: "I couldn't change task #{n}. Check the activity."

  def task_action_failed(_lang, _kind, n),
    do: "Não consegui mudar a tarefa #{n}. Veja a atividade."

  def task_not_found("en-US", n), do: "I can't find task #{n} in this project."
  def task_not_found(_lang, n), do: "Não achei a tarefa #{n} neste projeto."

  def repository_not_found("en-US", name), do: "I don't follow a project called #{name}."
  def repository_not_found(_lang, name), do: "Não acompanho nenhum projeto chamado #{name}."

  def cancelled("en-US"), do: "Okay, I won't do it."
  def cancelled(_lang), do: "Tudo bem, deixei pra lá."

  def already_settled("en-US"), do: "That was already handled."
  def already_settled(_lang), do: "Isso já foi resolvido."

  def forgot("en-US"), do: "Done, I forgot our conversation. Fresh start."
  def forgot(_lang), do: "Pronto, esqueci a nossa conversa. Começando do zero."

  def didnt_hear("en-US"), do: "I didn't hear anything."
  def didnt_hear(_lang), do: "Não ouvi nada."

  def too_slow("en-US"), do: "That took too long, so I stopped. Ask me again."
  def too_slow(_lang), do: "Demorei demais e parei. Pode me pedir de novo."

  @doc "The section headings of an issue body written from a spoken request."
  def issue_labels("en-US"),
    do: %{
      constraints: "Constraints",
      assumptions: "Assumptions",
      risks: "Risks",
      open_questions: "Open questions",
      spoken: "Spoken request"
    }

  def issue_labels(_lang),
    do: %{
      constraints: "Restrições",
      assumptions: "Premissas",
      risks: "Riscos",
      open_questions: "Perguntas em aberto",
      spoken: "Pedido por voz"
    }

  defp repo_name(slug), do: slug |> to_string() |> String.split("/") |> List.last()

  # ---- the status summary -------------------------------------------------

  @doc "The greeting for a local hour of the day."
  def greeting("en-US", h) when h < 12, do: "Good morning"
  def greeting("en-US", h) when h < 18, do: "Good afternoon"
  def greeting("en-US", _h), do: "Good evening"
  def greeting(_lang, h) when h < 12, do: "Bom dia"
  def greeting(_lang, h) when h < 18, do: "Boa tarde"
  def greeting(_lang, _h), do: "Boa noite"

  @doc "A count for the spoken summary, e.g. `2 na fila`."
  def count("en-US", key, n) do
    case key do
      :running -> "#{n} running"
      :question -> "#{n} waiting for your answer"
      :ready -> "#{n} ready for review"
      :blocked -> "#{n} blocked"
      :merged -> "#{n} recent #{plural(n, "merge", "merges")}"
      :queued -> "#{n} queued"
    end
  end

  def count(_lang, key, n) do
    case key do
      :running -> "#{n} em andamento"
      :question -> "#{n} esperando sua resposta"
      :ready -> "#{n} #{plural(n, "pronta", "prontas")} para revisão"
      :blocked -> "#{n} #{plural(n, "bloqueada", "bloqueadas")}"
      :merged -> "#{n} #{plural(n, "entrega recente", "entregas recentes")}"
      :queued -> "#{n} na fila"
    end
  end

  @doc "The summary sentence for the counts (already spoken with `count/3`)."
  def summary(lang, greeting, []), do: "#{greeting}. #{calm(lang)}"
  def summary(lang, greeting, parts), do: "#{greeting}. #{on_board(lang)}: #{join(lang, parts)}."

  defp calm("en-US"), do: "The board is calm: nothing is running and nothing needs you."
  defp calm(_lang), do: "Tudo tranquilo: nada rodando e nada esperando por você."

  defp on_board("en-US"), do: "On the board"
  defp on_board(_lang), do: "No quadro"

  @doc "Joins items as a spoken list: `a, b and c` / `a, b e c`."
  def join(_lang, [one]), do: one

  def join(lang, many) do
    Enum.join(Enum.drop(many, -1), ", ") <> " #{conjunction(lang)} " <> List.last(many)
  end

  defp conjunction("en-US"), do: "and"
  defp conjunction(_lang), do: "e"

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  defp lang_map(map, lang), do: Map.get(map, lang) || Map.fetch!(map, @default)

  defp pick(pool, turn) when is_integer(turn), do: Enum.at(pool, rem(abs(turn), length(pool)))

  defp fill(phrase, title), do: String.replace(phrase, "%{t}", short_title(title))
end
