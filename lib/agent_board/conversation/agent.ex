defmodule AgentBoard.Conversation.Agent do
  @moduledoc """
  One spoken turn of the owner's conversation: understand it, act on the
  board when asked, and answer in one short spoken reply.

  The order is deliberate:

    1. A yes or no to the proposal waiting for one is recognized locally
       (no model, no cost, no latency), and so are the short commands
       ("status", "ajuda", "desfaz", "repete", "mais devagar").
    2. Anything else goes to the registered `:voice_agent` call with the
       conversation memory, the waiting proposal and a compact board
       snapshot; the answer names one action.
    3. Reads (status, open a task, switch project) happen at once. A `look`
       (one task in depth, the runs, the failures, a search, the day) reads
       the board's own data (`AgentBoard.Conversation.Lookup`) and a second
       call, `:voice_explain`, answers only from those facts. Writes
       (create, stop or archive a task) become a **proposal** the owner
       confirms by voice; a request for new work is refined in the same
       call (title and acceptance criteria), and an unclear one becomes a
       question. "Cria direto" creates at once, and "desfaz" closes that
       task within 10 minutes.

  The catalog the owner sees is `AgentBoard.Voice.Commands`.

  The coding agent is never involved: a created task is a GitHub issue the
  agent picks up on its own, exactly like the composer's.
  """

  alias AgentBoard.{AI, Board, Conversation, Repo, Titles}
  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.Conversation.{Lookup, Turn}
  alias AgentBoard.Voice.{Activity, Phrases}

  @lane_sample 8
  @lanes [:question, :blocked, :ready, :running, :queued]

  @yes ~w(sim pode claro confirmo confirma isso ok okay manda fechado beleza perfeito
          certo faz cria criar yes sure yep yeah confirm)
  @yes_phrases ["pode criar", "pode sim", "manda ver", "pode mandar", "go ahead", "do it"]
  @no ~w(nao cancela cancelar cancele deixa esquece negativo no nope cancel)
  @no_phrases ["deixa pra la", "deixa para la", "melhor nao", "agora nao", "not now"]

  @type context :: %{
          required(:language) => String.t(),
          required(:repo) => Repository.t() | nil,
          required(:repos) => [Repository.t()],
          required(:board) => map(),
          optional(:sync_event) => map() | nil,
          optional(:open_task) => Task.t() | nil,
          optional(:client) => term()
        }

  @type outcome :: %{
          reply: String.t(),
          action: String.t(),
          effect:
            nil
            | {:open_task, Task.t()}
            | {:select_repository, Repository.t()}
            | {:changed, Repository.t()}
            | :show_commands
            | :voice_changed,
          listen: boolean()
        }

  @doc """
  Answers one owner turn (already recorded by the caller) and records the
  agent's reply. Never raises: a model failure is a spoken sentence.
  """
  @spec respond(String.t(), context()) :: outcome()
  def respond(text, ctx) do
    started = System.monotonic_time(:millisecond)
    lang = ctx.language
    pending = Conversation.pending_proposal()

    outcome =
      case quick_answer(text, pending) do
        :yes -> confirm(pending, ctx)
        :no -> cancel(pending, lang)
        :none -> local_command(text, ctx) || think(text, pending, ctx)
      end

    record(outcome, ctx, System.monotonic_time(:millisecond) - started)
    outcome
  end

  @doc "Whether a short answer is a yes (`:yes`), a no (`:no`) or neither."
  @spec yes_or_no(String.t()) :: :yes | :no | :none
  def yes_or_no(text) when is_binary(text) do
    phrase = normalize(text)
    words = String.split(phrase, " ", trim: true)

    cond do
      words == [] or length(words) > 6 -> :none
      String.starts_with?(phrase, ["nao sei", "no idea"]) -> :none
      starts_with_any?(phrase, words, @no, @no_phrases) -> :no
      starts_with_any?(phrase, words, @yes, @yes_phrases) -> :yes
      true -> :none
    end
  end

  # Short commands about the conversation itself never need the model:
  # "repete" says the last reply again, "mais devagar" / "mais alto" adjust
  # the voice. Long sentences are left to the model ("a tarefa de deixar o
  # jogo mais rápido" is a request, not a speed change).
  @repeat [
    "repete",
    "repita",
    "pode repetir",
    "repete por favor",
    "fala de novo",
    "de novo",
    "nao entendi",
    "o que",
    "como",
    "say again",
    "repeat",
    "repeat that"
  ]
  @voice_moves [
    {~r/\b(mais devagar|devagar|mais lento|fala devagar|slower)\b/u, :speed, -0.1},
    {~r/\b(mais rapido|mais depressa|fala rapido|faster)\b/u, :speed, 0.1},
    {~r/\b(mais alto|aumenta o volume|aumenta a voz|louder)\b/u, :volume, 20},
    {~r/\b(mais baixo|abaixa o volume|diminui o volume|baixa o volume|quieter)\b/u, :volume, -20}
  ]
  @help [
    "ajuda",
    "socorro",
    "comandos",
    "lista de comandos",
    "o que voce sabe fazer",
    "o que voce faz",
    "o que posso pedir",
    "o que eu posso pedir",
    "o que eu posso falar",
    "help",
    "commands",
    "what can you do",
    "what can i say"
  ]
  @status ["status", "resumo", "status rapido", "resumo rapido", "status do quadro", "summary"]
  @undo [
    "desfaz",
    "desfazer",
    "desfaca",
    "desfaz isso",
    "desfaz a ultima",
    "desfaz a tarefa",
    "undo",
    "undo that"
  ]

  @doc false
  def local_command(text, ctx) do
    lang = ctx.language
    phrase = normalize(text)
    words = phrase |> String.split(" ", trim: true) |> length()

    cond do
      words == 0 or words > 6 ->
        nil

      phrase in @repeat ->
        repeat(lang)

      phrase in @help ->
        help(lang)

      phrase in @status ->
        status(ctx)

      phrase in @undo ->
        undo(ctx)

      move = Enum.find(@voice_moves, fn {re, _, _} -> Regex.match?(re, phrase) end) ->
        adjust(move, lang)

      true ->
        nil
    end
  end

  defp repeat(lang) do
    case Conversation.last_agent_text() do
      nil -> say(Phrases.not_understood(lang), "repeat")
      text -> say(text, "repeat")
    end
  end

  defp help(lang), do: %{say(Phrases.help(lang), "help") | effect: :show_commands}

  # The template summary, with the exact lane totals: instant and free.
  defp status(ctx) do
    text =
      AgentBoard.Voice.summary(ctx.board || %{},
        language: ctx.language,
        tz_offset: Map.get(ctx, :tz_offset, 0)
      )

    say(text, "status")
  end

  # "Desfaz" closes the newest task the voice created in the last 10
  # minutes. The claim is conditional, so a repeated "desfaz" closes once.
  defp undo(ctx) do
    lang = ctx.language

    with %Turn{proposal: %{"task_id" => id, "number" => n}} = turn <- Conversation.last_created(),
         :ok <- Conversation.mark_undone(turn) do
      result =
        case Repo.get(Task, id) do
          nil -> {:error, :not_found}
          task -> Board.stop_task(task, client(ctx))
        end

      case result do
        {:ok, task} ->
          Activity.record(:action, :ok, "desfeito: tarefa ##{n} fechada", turn: ctx[:turn_id])
          repo = Repo.get(Repository, task.repository_id)
          %{say(Phrases.undone(lang, n), "undo") | effect: repo && {:changed, repo}}

        failure ->
          Activity.record(:action, :error, "não consegui desfazer a tarefa ##{n}",
            turn: ctx[:turn_id],
            reason: create_failure(failure)
          )

          say(Phrases.undo_failed(lang, n), "undo")
      end
    else
      _ -> say(Phrases.nothing_to_undo(lang), "undo")
    end
  end

  defp adjust({_re, :speed, delta}, lang) do
    current = AgentBoard.Voice.speed()
    target = Float.round(min(max(current + delta, 0.8), 1.2), 2)

    if target == current do
      say(Phrases.voice_at_limit(lang, :speed, delta), "adjust_voice")
    else
      :ok = AgentBoard.Voice.put_speed(target)
      %{say(Phrases.voice_adjusted(lang, :speed, delta), "adjust_voice") | effect: :voice_changed}
    end
  end

  defp adjust({_re, :volume, delta}, lang) do
    current = AgentBoard.Voice.volume()
    target = min(max(current + delta, 0), 100)

    if target == current do
      say(Phrases.voice_at_limit(lang, :volume, delta), "adjust_voice")
    else
      :ok = AgentBoard.Voice.put_volume(target)

      %{
        say(Phrases.voice_adjusted(lang, :volume, delta), "adjust_voice")
        | effect: :voice_changed
      }
    end
  end

  defp quick_answer(_text, nil), do: :none
  defp quick_answer(text, %Turn{}), do: yes_or_no(text)

  defp starts_with_any?(phrase, [first | _], words, phrases) do
    first in words or Enum.any?(phrases, &String.starts_with?(phrase, &1))
  end

  # ---- the model ------------------------------------------------------------

  defp think(text, pending, ctx) do
    ctx = Map.put(ctx, :utterance, text)

    inputs = %{
      language: ctx.language,
      utterance: text,
      memory: Conversation.context(),
      pending: pending_fact(pending),
      board: snapshot(ctx)
    }

    # Compact JSON, without the default's indentation.
    started = System.monotonic_time(:millisecond)

    case AI.call(:voice_agent, %{prompt: "Inputs:\n" <> Jason.encode!(inputs)}) do
      {:ok, %{json: %{"action" => action} = json}} ->
        Activity.record(:model, :ok, "decidiu: #{action}",
          turn: ctx[:turn_id],
          ms: System.monotonic_time(:millisecond) - started
        )

        act(action, json, pending, ctx)

      {:ok, _result} ->
        Activity.record(:model, :error, "a resposta do modelo veio fora do formato",
          turn: ctx[:turn_id],
          ms: System.monotonic_time(:millisecond) - started
        )

        say(Phrases.not_understood(ctx.language), "error")

      {:error, reason} ->
        Activity.record(:model, :error, "o modelo não respondeu",
          turn: ctx[:turn_id],
          ms: System.monotonic_time(:millisecond) - started,
          reason: reason
        )

        say(Phrases.ai_failed(ctx.language, reason), "error")
    end
  end

  defp act("reply", json, _pending, ctx), do: say(reply(json, ctx), "reply")

  defp act("confirm", json, %Turn{} = pending, ctx) do
    _ = json
    confirm(pending, ctx)
  end

  defp act("cancel", _json, %Turn{} = pending, ctx), do: cancel(pending, ctx.language)

  defp act(action, json, nil, ctx) when action in ~w(confirm cancel),
    do: say(reply(json, ctx), "reply")

  defp act("forget", _json, _pending, ctx) do
    :ok = Conversation.clear()
    say(Phrases.forgot(ctx.language), "forget")
  end

  defp act("open_task", %{"task_number" => n} = json, _pending, ctx) do
    case find_task(ctx.repo, n) do
      %Task{} = task ->
        %{say(reply(json, ctx), "open_task") | effect: {:open_task, task}}

      nil ->
        say(Phrases.task_not_found(ctx.language, n), "open_task")
    end
  end

  defp act("select_repository", %{"repository" => name} = json, _pending, ctx) do
    case match_repository(ctx.repos, name) do
      %Repository{} = repo ->
        %{say(reply(json, ctx), "select_repository") | effect: {:select_repository, repo}}

      nil ->
        say(Phrases.repository_not_found(ctx.language, name), "select_repository")
    end
  end

  defp act("create_task", json, _pending, ctx), do: propose_task(json, ctx)

  defp act("look", json, _pending, ctx), do: look(json["lookup"], json, ctx)
  defp act("help", _json, _pending, ctx), do: help(ctx.language)
  defp act("undo", _json, _pending, ctx), do: undo(ctx)

  defp act(action, %{"task_number" => n}, _pending, ctx)
       when action in ~w(stop_task archive_task),
       do: propose_task_action(action, n, ctx)

  defp act("ask_task", %{"task_number" => n, "request" => question} = json, _pending, ctx) do
    task = find_task(ctx.repo, n) || Map.get(ctx, :open_task)
    question = String.trim(question || "")

    cond do
      question == "" -> say(reply(json, ctx), "ask_task")
      is_nil(task) -> say(Phrases.task_not_found(ctx.language, n), "ask_task")
      true -> propose_ask(task, question, ctx)
    end
  end

  defp act(_action, json, _pending, ctx), do: say(reply(json, ctx), "reply")

  # ---- reads with a second step ----------------------------------------------

  # The board reads its own data, then `:voice_explain` answers from it. A
  # missing task, an empty search or no project is said without a model.
  defp look(kind, json, ctx) do
    lang = ctx.language
    number = json["task_number"]

    args = %{
      task_number: number,
      query: if(blank?(json["request"]), do: ctx[:utterance], else: json["request"])
    }

    case Lookup.facts(kind, ctx, args) do
      {:ok, facts, effect} ->
        %{explain(kind, facts, ctx) | effect: effect}

      {:error, :task_not_found} when is_integer(number) and number > 0 ->
        say(Phrases.task_not_found(lang, number), "look")

      {:error, :task_not_found} ->
        listen(say(Phrases.which_task(lang), "look"))

      {:error, :empty_query} ->
        listen(say(Phrases.search_what(lang), "look"))

      {:error, :no_repository} ->
        say(Phrases.no_project(lang), "look")

      {:error, :unknown_lookup} ->
        say(reply(json, ctx), "reply")
    end
  end

  defp explain(kind, facts, ctx) do
    started = System.monotonic_time(:millisecond)

    inputs = %{
      language: ctx.language,
      question: ctx[:utterance],
      lookup: kind,
      facts: facts
    }

    case AI.call(:voice_explain, %{prompt: "Inputs:\n" <> Jason.encode!(inputs)}) do
      {:ok, %{json: %{"reply" => text}}} when is_binary(text) and text != "" ->
        Activity.record(:model, :ok, "explicou a partir do quadro (#{kind})",
          turn: ctx[:turn_id],
          ms: System.monotonic_time(:millisecond) - started
        )

        say(text, "look_" <> kind)

      {:ok, _result} ->
        Activity.record(:model, :error, "a explicação veio fora do formato",
          turn: ctx[:turn_id],
          ms: System.monotonic_time(:millisecond) - started
        )

        say(Phrases.not_understood(ctx.language), "error")

      {:error, reason} ->
        Activity.record(:model, :error, "o modelo não explicou",
          turn: ctx[:turn_id],
          ms: System.monotonic_time(:millisecond) - started,
          reason: reason
        )

        say(Phrases.ai_failed(ctx.language, reason), "error")
    end
  end

  defp blank?(text), do: String.trim(text || "") == ""

  # ---- proposals ------------------------------------------------------------

  # The model refines the request in the same call that understood it: a
  # second refine call cost 5-7 s of silence before "Posso criar?".
  defp propose_task(%{"request" => request} = json, ctx) do
    lang = ctx.language
    repo = match_repository(ctx.repos, json["repository"]) || ctx.repo

    cond do
      blank?(request) ->
        say(reply(json, ctx), "create_task")

      is_nil(repo) ->
        listen(say(Phrases.which_project(lang), "create_task"))

      # "Cria direto": no question back, no "Posso criar?".
      json["direct"] == true ->
        json |> new_task(request, repo, lang) |> create_direct(ctx)

      not blank?(json["question"]) ->
        listen(say(Phrases.clarify(lang, String.trim(json["question"])), "create_task"))

      true ->
        task = new_task(json, request, repo, lang)
        proposal(task, Phrases.propose_task(lang, slug(repo), task["title"]))
    end
  end

  defp new_task(json, request, repo, lang) do
    %{
      "kind" => "create_task",
      "repository_id" => repo.id,
      "repository" => slug(repo),
      "title" => title(json["title"], request),
      "body" => body(json["details"], request, lang)
    }
  end

  # The owner said "cria direto": no "Posso criar?", and "desfaz" takes it
  # back for 10 minutes (the reply says so).
  defp create_direct(task, ctx) do
    Activity.record(:action, :info, "pedido direto: cria sem perguntar", turn: ctx[:turn_id])

    case execute(task, ctx) do
      %{proposal: %{"kind" => "created", "number" => n, "repository" => slug}} = outcome ->
        %{outcome | reply: Phrases.task_created_direct(ctx.language, n, slug)}

      outcome ->
        outcome
    end
  end

  defp propose_task_action(action, number, ctx) do
    lang = ctx.language

    case find_task(ctx.repo, number) do
      %Task{} = task when task.stopped == false and task.archived == false ->
        kind = if action == "stop_task", do: "stop_task", else: "archive_task"

        proposal(
          %{
            "kind" => kind,
            "task_id" => task.id,
            "number" => task.number,
            "title" => task.title,
            "repository_id" => task.repository_id
          },
          Phrases.propose_task_action(lang, kind, task.number, task.title || "")
        )

      _ ->
        say(Phrases.task_not_found(lang, number), action)
    end
  end

  defp propose_ask(task, question, ctx) do
    proposal(
      %{
        "kind" => "ask_task",
        "task_id" => task.id,
        "number" => task.number,
        "question" => question,
        "repository_id" => task.repository_id
      },
      Phrases.propose_ask(ctx.language, task.number, question)
    )
  end

  defp proposal(proposal, text) do
    :ok = Conversation.supersede_proposals()
    Activity.record(:action, :info, "proposta aguardando o seu sim: #{proposal["kind"]}")

    %{
      reply: text,
      action: "propose_" <> proposal["kind"],
      effect: nil,
      listen: true,
      proposal: proposal
    }
  end

  defp title(title, request) do
    case String.trim(title || "") do
      "" -> Titles.from_request(request)
      title -> Titles.from_request(title)
    end
  end

  defp body(details, request, lang) do
    labels = Phrases.issue_labels(lang)
    details = Enum.filter(List.wrap(details), &(is_binary(&1) and String.trim(&1) != ""))

    [
      section(labels.acceptance, details),
      "> #{labels.spoken}: \"#{String.trim(request)}\""
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp section(_label, []), do: nil
  defp section(label, items), do: "**#{label}**\n" <> Enum.map_join(items, "\n", &"- #{&1}")

  # ---- confirmation ---------------------------------------------------------

  defp confirm(%Turn{proposal: proposal} = pending, ctx) do
    lang = ctx.language

    case Conversation.settle(pending, "confirmed") do
      :ok -> execute(proposal, ctx)
      :already_settled -> say(Phrases.already_settled(lang), "confirm")
    end
  end

  defp cancel(%Turn{} = pending, lang) do
    _ = Conversation.settle(pending, "cancelled")
    say(Phrases.cancelled(lang), "cancel")
  end

  defp execute(%{"kind" => "create_task"} = p, ctx) do
    lang = ctx.language

    with %Repository{} = repo <- Repo.get(Repository, p["repository_id"]),
         key = Board.request_key(repo, "voice", [p["title"], p["body"]]),
         {:ok, task, outcome} <-
           Board.create_request(
             repo,
             %{title: p["title"], body: p["body"], key: key},
             client(ctx)
           ) do
      text =
        if outcome == :created,
          do: Phrases.task_created(lang, task.number, slug(repo)),
          else: Phrases.task_existing(lang, task.number)

      Activity.record(
        :action,
        :ok,
        "tarefa ##{task.number} #{if outcome == :created, do: "criada", else: "já existia"} em #{slug(repo)}",
        turn: ctx[:turn_id]
      )

      said = %{say(text, "create_task") | effect: {:changed, repo}}

      # Only a task this turn created can be undone; one that already
      # existed belongs to whoever opened it.
      if outcome == :created, do: created(said, task, repo), else: said
    else
      failure ->
        Activity.record(:action, :error, "não consegui criar a tarefa",
          turn: ctx[:turn_id],
          reason: create_failure(failure)
        )

        say(Phrases.task_failed(lang), "create_task")
    end
  end

  defp execute(%{"kind" => kind, "task_id" => id} = p, ctx)
       when kind in ~w(stop_task archive_task) do
    lang = ctx.language
    task = id && Repo.get(Task, id)

    result =
      case {kind, task} do
        {_, nil} -> {:error, :not_found}
        {"stop_task", task} -> Board.stop_task(task, client(ctx))
        {"archive_task", task} -> Board.archive_task(task)
      end

    case result do
      {:ok, _} ->
        Board.broadcast(task.repository_id)
        repo = Repo.get(Repository, task.repository_id)

        %{
          say(Phrases.task_action_done(lang, kind, p["number"]), kind)
          | effect: repo && {:changed, repo}
        }

      failure ->
        Activity.record(:action, :error, "não consegui mudar a tarefa ##{p["number"]}",
          turn: ctx[:turn_id],
          reason: create_failure(failure)
        )

        say(Phrases.task_action_failed(lang, kind, p["number"]), kind)
    end
  end

  defp execute(%{"kind" => "ask_task", "task_id" => id} = p, ctx) do
    lang = ctx.language

    with %Task{} = task <- id && Repo.get(Task, id),
         {:ok, _comment} <- Board.ask(task, p["question"], client(ctx)) do
      Activity.record(:action, :ok, "pergunta enviada ao agente na tarefa ##{p["number"]}",
        turn: ctx[:turn_id]
      )

      say(Phrases.ask_sent(lang, p["number"]), "ask_task")
    else
      failure ->
        Activity.record(:action, :error, "a pergunta não foi enviada na tarefa ##{p["number"]}",
          turn: ctx[:turn_id],
          reason: create_failure(failure)
        )

        say(Phrases.ask_failed(lang, p["number"]), "ask_task")
    end
  end

  defp execute(_proposal, ctx), do: say(Phrases.task_failed(ctx.language), "confirm")

  defp created(outcome, task, repo) do
    outcome
    |> Map.put(:proposal, %{
      "kind" => "created",
      "task_id" => task.id,
      "number" => task.number,
      "repository" => slug(repo)
    })
    |> Map.put(:proposal_status, "done")
  end

  defp create_failure({:error, reason}), do: reason
  defp create_failure(nil), do: :repository_missing
  defp create_failure(other), do: other

  defp client(ctx), do: Map.get_lazy(ctx, :client, &AgentBoard.GitHub.client/0)

  # ---- facts for the model --------------------------------------------------

  defp pending_fact(nil), do: nil

  defp pending_fact(%Turn{proposal: proposal, text: text}),
    do: %{asked: text, proposal: Map.drop(proposal || %{}, ["body"])}

  @doc "The compact board the model reads: titles are data, counts are exact."
  def snapshot(ctx) do
    board = ctx.board || %{}
    counts = Map.get(board, :task_counts) || %{}

    %{
      current_repository: ctx.repo && slug(ctx.repo),
      repositories: Enum.map(ctx.repos || [], &slug/1),
      open_task: task_fact(Map.get(ctx, :open_task)),
      lanes:
        Map.new(@lanes, fn lane ->
          rows = Map.get(board, lane) || []

          {lane,
           %{
             total: Map.get(counts, lane, length(rows)),
             tasks: rows |> Enum.take(@lane_sample) |> Enum.map(&task_fact/1)
           }}
        end),
      recent_merges:
        (Map.get(board, :merged) || [])
        |> Enum.take(5)
        |> Enum.map(&%{number: Map.get(&1, :number), title: Map.get(&1, :title)}),
      sync: sync_fact(Map.get(ctx, :sync_event))
    }
  end

  defp task_fact(nil), do: nil

  defp task_fact(task) do
    %{number: Map.get(task, :number), title: Map.get(task, :title), state: Map.get(task, :state)}
  end

  defp sync_fact(%{kind: kind, inserted_at: at}),
    do: %{last: kind, at: at && DateTime.to_iso8601(at)}

  defp sync_fact(_event), do: nil

  # ---- helpers --------------------------------------------------------------

  defp say(text, action),
    do: %{reply: text, action: action, effect: nil, listen: false, proposal: nil}

  defp listen(outcome), do: %{outcome | listen: true}

  defp reply(%{"reply" => text}, _ctx) when is_binary(text) and text != "", do: text
  defp reply(_json, ctx), do: Phrases.not_understood(ctx.language)

  defp record(outcome, ctx, duration_ms) do
    Conversation.record("agent", outcome.reply,
      repository_id: ctx.repo && ctx.repo.id,
      action: outcome.action,
      proposal: outcome.proposal,
      proposal_status: Map.get(outcome, :proposal_status),
      duration_ms: duration_ms
    )
  end

  defp find_task(nil, _number), do: nil
  defp find_task(repo, n) when is_integer(n) and n > 0, do: Board.find_task(repo, n)
  defp find_task(_repo, _number), do: nil

  @doc "The tracked repository a spoken name points at (`arena rogue` → `owner/arena-rogue`)."
  def match_repository(_repos, name) when name in [nil, ""], do: nil

  def match_repository(repos, name) do
    wanted = squash(name)

    Enum.find(repos, &(squash(slug(&1)) == wanted)) ||
      Enum.find(repos, &(squash(&1.name) == wanted)) ||
      Enum.find(repos, &String.contains?(squash(&1.name), wanted)) ||
      Enum.find(repos, &String.contains?(wanted, squash(&1.name)))
  end

  defp squash(text), do: text |> normalize() |> String.replace(~r/[^a-z0-9\/]/u, "")

  defp slug(%Repository{owner: owner, name: name}), do: "#{owner}/#{name}"

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^\p{L}\p{N}\/\s-]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
