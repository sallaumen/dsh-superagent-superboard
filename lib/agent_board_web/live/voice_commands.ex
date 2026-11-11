defmodule AgentBoardWeb.VoiceCommands do
  @moduledoc "Deterministic read-only commands against the board's saved snapshot."
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Board
  alias AgentBoardWeb.BoardNavigation

  @activity ~w(atividade activity)
  @ai ["ia", "ai", "chamadas de ia", "ai calls", "painel de ia", "ai panel"]
  @status ["status", "resumo", "board status", "estado do board", "situacao do board"]
  @blocked [
    "bloqueados",
    "bloqueadas",
    "blocked",
    "o que esta bloqueado",
    "what is blocked",
    "mostrar tarefas bloqueadas",
    "show blocked tasks"
  ]
  @verbs ~w(abrir abra mostrar mostre encontrar encontre find open show)
  @ask_prefixes ~w(perguntar pergunte ask)
  @repo_verbs [
    "selecionar",
    "selecione",
    "mudar para",
    "trocar para",
    "switch to",
    "select",
    "open",
    "abrir",
    "abra"
  ]

  @doc "Return a result for the command draft and, when appropriate, a board URL."
  def resolve(text, context) when is_binary(text) and is_map(context) do
    case parse(text) do
      {:ask, question} -> ask(context, question)
      intent -> read_only(intent, context)
    end
  end

  defp read_only({:panel, panel}, context), do: open_panel(context, panel)
  defp read_only({:repository, slug}, context), do: select_repository(context, slug)
  defp read_only({:task, number}, context), do: find_task(context, number)
  defp read_only({:pull_request, number}, context), do: find_pull_request(context, number)
  defp read_only(:status, context), do: status(context)
  defp read_only(:blocked, context), do: blocked(context)

  defp read_only(:unknown, _context) do
    reply(
      :unknown,
      gettext(
        "Command not recognized. Try status, activity, AI calls, repo owner/name, task #42, or PR #42. Your draft is still here."
      )
    )
  end

  @doc """
  Parse explicit board commands; other text stays a draft.

  A draft ending in a question mark is an ask intent only when no read-only
  command matched it, so "O que está bloqueado?" still opens the blocked
  report.
  """
  def parse(text) when is_binary(text) do
    trimmed = String.trim(text)

    case prefixed_ask(trimmed) do
      nil -> read_only_intent(trimmed)
      question -> {:ask, question}
    end
  end

  defp read_only_intent(trimmed) do
    phrase = if byte_size(trimmed) <= 500, do: normalize(trimmed), else: ""
    intent(phrase, trimmed)
  end

  defp intent(phrase, trimmed) do
    cond do
      phrase in @status -> :status
      phrase in @blocked -> :blocked
      true -> intent_by_shape(phrase, trimmed)
    end
  end

  defp intent_by_shape(phrase, trimmed) do
    cond do
      panel = panel(phrase) -> {:panel, panel}
      slug = repository_slug(phrase) -> {:repository, slug}
      true -> intent_by_number(phrase, trimmed)
    end
  end

  defp intent_by_number(phrase, trimmed) do
    cond do
      number = numbered(phrase, "(?:tarefa|task|issue)") -> {:task, number}
      number = numbered(phrase, "(?:pr|pull request)") -> {:pull_request, number}
      true -> question_or_unknown(trimmed)
    end
  end

  defp question_or_unknown(trimmed) do
    if String.ends_with?(trimmed, "?"), do: {:ask, trimmed}, else: :unknown
  end

  defp prefixed_ask(text) do
    lower = String.downcase(text)

    case Enum.find(@ask_prefixes, &String.starts_with?(lower, &1 <> " ")) do
      nil -> nil
      prefix -> text |> String.slice(byte_size(prefix)..-1//1) |> String.trim() |> blank_to_nil()
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp normalize(text) do
    text
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim_trailing("?")
    |> String.trim_trailing(".")
  end

  defp panel(phrase) do
    words = String.split(phrase, " ")
    words = if List.first(words) in @verbs, do: tl(words), else: words
    words = Enum.drop_while(words, &(&1 in ["o", "a", "the", "painel", "de", "do"]))
    target = Enum.join(words, " ")

    cond do
      target in @activity -> "activity"
      target in @ai -> "ai"
      true -> nil
    end
  end

  defp repository_slug(phrase) do
    prefix = Enum.find(@repo_verbs, &String.starts_with?(phrase, &1 <> " "))
    rest = if prefix, do: String.replace_prefix(phrase, prefix <> " ", ""), else: phrase
    rest = String.replace(rest, ~r/\A(?:o |a |the )?(?:repositorio|repository|repo) /u, "")

    if Regex.match?(~r/\A[[:alnum:]_.-]+\/[[:alnum:]_.-]+\z/u, rest), do: rest
  end

  defp numbered(phrase, noun) do
    verbs = Enum.join(@verbs, "|")
    regex = ~r/\A(?:(?:#{verbs}) )?(?:o |a |the )?#{noun} #?(\d{1,9})\z/u

    case Regex.run(regex, phrase, capture: :all_but_first) do
      [number] -> String.to_integer(number)
      _ -> nil
    end
  end

  defp open_panel(%{repo: nil}, _panel), do: missing_repository()

  defp open_panel(%{repo: repo}, panel) do
    text =
      if panel == "ai",
        do: gettext("Opened AI calls for %{repo}.", repo: slug(repo)),
        else: gettext("Opened Activity for %{repo}.", repo: slug(repo))

    reply(:success, text, BoardNavigation.path(repo, panel))
  end

  defp select_repository(%{repos: repos}, requested) do
    case Enum.find(repos, &(normalize(slug(&1)) == requested)) do
      nil ->
        reply(
          :unknown,
          gettext("Repository %{name} is not tracked by this board. Your draft is still here.",
            name: requested
          )
        )

      repo ->
        reply(
          :success,
          gettext("Selected %{repo}.", repo: slug(repo)),
          BoardNavigation.path(repo)
        )
    end
  end

  defp find_task(%{repo: nil}, _number), do: missing_repository()

  defp find_task(%{repo: repo, sync_event: sync_event}, number) do
    case Board.find_task(repo, number) do
      nil ->
        reply(
          :unknown,
          gettext(
            "Task #%{number} is not in the saved data for %{repo}. %{sync} Your draft is still here.",
            number: number,
            repo: slug(repo),
            sync: sync_note(sync_event)
          )
        )

      task ->
        result = %{
          kind: :success,
          text:
            gettext("Task #%{number}: %{title}. Saved state: %{state}. Updated %{time}.",
              number: number,
              title: task.title || gettext("unknown"),
              state: task.state || gettext("unknown"),
              time: timestamp(task.updated_at)
            ),
          as_of: task.updated_at,
          source: gettext("Task record updated")
        }

        %{result: result, path: BoardNavigation.path(repo, "conversation", task.id)}
    end
  end

  defp find_pull_request(%{repo: nil}, _number), do: missing_repository()

  defp find_pull_request(%{repo: repo, sync_event: sync_event}, number) do
    case Board.find_pull_request(repo, number) do
      nil ->
        reply(
          :unknown,
          gettext(
            "PR #%{number} is not in the saved data for %{repo}. %{sync} Your draft is still here.",
            number: number,
            repo: slug(repo),
            sync: sync_note(sync_event)
          )
        )

      pr ->
        %{
          result: %{
            kind: :success,
            text:
              gettext("PR #%{number}: %{title}. Saved state: %{state}. Updated %{time}.",
                number: number,
                title: pr.title || gettext("unknown"),
                state: pr.state || gettext("unknown"),
                time: timestamp(pr.updated_at)
              ),
            as_of: pr.updated_at,
            source: gettext("PR record updated"),
            url: safe_url(pr.url)
          },
          path: nil
        }
    end
  end

  defp status(%{repo: nil}), do: missing_repository()

  defp status(%{repo: repo, board: board, sync_event: sync_event}) do
    counts = board.task_counts

    text =
      gettext(
        "Saved active lanes for %{repo}: %{running} running, %{ready} ready, %{blocked} blocked, %{queued} queued. %{sync}",
        repo: slug(repo),
        running: counts.running,
        ready: counts.ready,
        blocked: counts.blocked,
        queued: counts.queued,
        sync: sync_note(sync_event)
      )

    reply(:success, text, nil, sync_time(sync_event), sync_source(sync_event))
  end

  defp blocked(%{repo: nil}), do: missing_repository()

  defp blocked(%{repo: repo, board: board, sync_event: sync_event}) do
    count = board.task_counts.blocked

    recent =
      board
      |> Map.get(:blocked, [])
      |> Enum.take(3)
      |> Enum.map_join(
        ", ",
        &"##{&1.number || gettext("unknown")} #{&1.title || gettext("unknown")}"
      )

    text =
      if recent == "" do
        gettext("Saved board for %{repo}: %{count} blocked tasks. %{sync}",
          repo: slug(repo),
          count: count,
          sync: sync_note(sync_event)
        )
      else
        gettext(
          "Saved board for %{repo}: %{count} blocked tasks. Recent blocked cards: %{recent}. %{sync}",
          repo: slug(repo),
          count: count,
          recent: recent,
          sync: sync_note(sync_event)
        )
      end

    reply(:success, text, nil, sync_time(sync_event), sync_source(sync_event))
  end

  defp ask(%{conversation: nil}, _question) do
    reply(
      :error,
      gettext("Open a task first and ask the question. Your draft stays here.")
    )
  end

  defp ask(%{conversation: task}, question) do
    %{
      result: %{
        kind: :ask,
        text:
          gettext("Ask task #%{number}: %{question}", number: task.number, question: question),
        question: question,
        task_number: task.number,
        task_id: task.id,
        task_updated_at: task.updated_at,
        repository_id: task.repository_id,
        as_of: nil
      },
      path: nil
    }
  end

  defp missing_repository,
    do:
      reply(
        :error,
        gettext(
          "Choose a tracked repository before using this board command. Your draft is still here."
        )
      )

  defp reply(kind, text, path \\ nil, as_of \\ nil, source \\ nil) do
    result = %{kind: kind, text: text, as_of: as_of}
    result = if source, do: Map.put(result, :source, source), else: result
    %{result: result, path: path}
  end

  defp sync_time(%{kind: "sync", inserted_at: at}), do: at
  defp sync_time(_), do: nil

  defp sync_source(%{kind: "sync"}), do: gettext("Last completed sync")
  defp sync_source(_), do: nil

  defp sync_note(%{kind: "sync", inserted_at: at}),
    do: gettext("Last completed sync: %{time}.", time: timestamp(at))

  defp sync_note(%{kind: "sync_error", inserted_at: at}),
    do:
      gettext("Latest sync failed at %{time}; showing saved data of unknown age.",
        time: timestamp(at)
      )

  defp sync_note(_), do: gettext("No sync yet; saved data age is unknown.")

  defp timestamp(nil), do: gettext("unknown")
  defp timestamp(at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp safe_url("https://github.com/" <> _ = url), do: url
  defp safe_url(_), do: nil

  defp slug(repo), do: "#{repo.owner}/#{repo.name}"
end
