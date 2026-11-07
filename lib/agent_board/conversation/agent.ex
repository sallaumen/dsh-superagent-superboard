defmodule AgentBoard.Conversation.Agent do
  @moduledoc """
  One spoken turn of the owner's conversation: understand it, act on the
  board when asked, and answer in one short spoken reply.

  The order is deliberate:

    1. A yes or no to the proposal waiting for one is recognized locally
       (no model, no cost, no latency).
    2. Anything else goes to the registered `:voice_agent` call with the
       conversation memory, the waiting proposal and a compact board
       snapshot; the answer names one action.
    3. Reads (status, open a task, switch project) happen at once. Writes
       (create, stop or archive a task) become a **proposal** the owner
       confirms by voice; a request for new work is first refined
       (`AgentBoard.Intake.refine/1`), and an unclear one becomes a question.

  The coding agent is never involved: a created task is a GitHub issue the
  agent picks up on its own, exactly like the composer's.
  """

  alias AgentBoard.{AI, Board, Conversation, Intake, Repo, Titles}
  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.Conversation.Turn
  alias AgentBoard.Voice.Phrases

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
            | {:changed, Repository.t()},
          listen: boolean()
        }

  @doc """
  Answers one owner turn (already recorded by the caller) and records the
  agent's reply. Never raises: a model failure is a spoken sentence.
  """
  @spec respond(String.t(), context()) :: outcome()
  def respond(text, ctx) do
    lang = ctx.language
    pending = Conversation.pending_proposal()

    outcome =
      case quick_answer(text, pending) do
        :yes -> confirm(pending, ctx)
        :no -> cancel(pending, lang)
        :none -> think(text, pending, ctx)
      end

    record(outcome, ctx)
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

  defp quick_answer(_text, nil), do: :none
  defp quick_answer(text, %Turn{}), do: yes_or_no(text)

  defp starts_with_any?(phrase, [first | _], words, phrases) do
    first in words or Enum.any?(phrases, &String.starts_with?(phrase, &1))
  end

  # ---- the model ------------------------------------------------------------

  defp think(text, pending, ctx) do
    inputs = %{
      language: ctx.language,
      utterance: text,
      memory: Conversation.context(),
      pending: pending_fact(pending),
      board: snapshot(ctx)
    }

    case AI.call(:voice_agent, inputs) do
      {:ok, %{json: %{"action" => action} = json}} -> act(action, json, pending, ctx)
      {:ok, _result} -> say(Phrases.not_understood(ctx.language), "error")
      {:error, reason} -> say(Phrases.ai_failed(ctx.language, reason), "error")
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

  defp act(action, %{"task_number" => n}, _pending, ctx)
       when action in ~w(stop_task archive_task),
       do: propose_task_action(action, n, ctx)

  defp act(_action, json, _pending, ctx), do: say(reply(json, ctx), "reply")

  # ---- proposals ------------------------------------------------------------

  defp propose_task(%{"request" => request} = json, ctx) do
    lang = ctx.language
    repo = match_repository(ctx.repos, json["repository"]) || ctx.repo

    cond do
      String.trim(request || "") == "" ->
        say(reply(json, ctx), "create_task")

      is_nil(repo) ->
        listen(say(Phrases.which_project(lang), "create_task"))

      true ->
        case Intake.refine(request) do
          {:ok, %{"ready" => false, "open_questions" => [question | _]}} ->
            listen(say(Phrases.clarify(lang, question), "create_task"))

          {:ok, spec} ->
            proposal(
              task_proposal(repo, request, spec, lang),
              Phrases.propose_task(lang, slug(repo), title(spec, request))
            )

          {:error, _reason} ->
            proposal(
              task_proposal(repo, request, %{}, lang),
              Phrases.propose_task(lang, slug(repo), title(%{}, request))
            )
        end
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

  defp proposal(proposal, text) do
    :ok = Conversation.supersede_proposals()

    %{
      reply: text,
      action: "propose_" <> proposal["kind"],
      effect: nil,
      listen: true,
      proposal: proposal
    }
  end

  defp task_proposal(repo, request, spec, lang) do
    title = title(spec, request)

    %{
      "kind" => "create_task",
      "repository_id" => repo.id,
      "repository" => slug(repo),
      "title" => title,
      "body" => body(spec, request, lang)
    }
  end

  defp title(%{"goal" => goal}, _request) when is_binary(goal) and goal != "",
    do: Titles.from_request(goal)

  defp title(_spec, request), do: Titles.from_request(request)

  defp body(spec, request, lang) do
    labels = Phrases.issue_labels(lang)

    [
      spec["goal"],
      section(labels.constraints, spec["constraints"]),
      section(labels.assumptions, spec["assumptions"]),
      section(labels.risks, spec["risks"]),
      section(labels.open_questions, spec["open_questions"]),
      "> #{labels.spoken}: \"#{String.trim(request)}\""
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp section(_label, items) when items in [nil, []], do: nil

  defp section(label, items) when is_list(items),
    do: "**#{label}**\n" <> Enum.map_join(items, "\n", &"- #{&1}")

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

      %{say(text, "create_task") | effect: {:changed, repo}}
    else
      _ -> say(Phrases.task_failed(lang), "create_task")
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

      _ ->
        say(Phrases.task_action_failed(lang, kind, p["number"]), kind)
    end
  end

  defp execute(_proposal, ctx), do: say(Phrases.task_failed(ctx.language), "confirm")

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

  defp record(outcome, ctx) do
    Conversation.record("agent", outcome.reply,
      repository_id: ctx.repo && ctx.repo.id,
      action: outcome.action,
      proposal: outcome.proposal
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
