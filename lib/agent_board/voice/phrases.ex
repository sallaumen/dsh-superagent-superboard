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
      ]
    }
  }

  @doc "The attention kinds: the states where the agent needs the owner."
  def attention_kinds, do: [:question, :blocked, :ready]

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
