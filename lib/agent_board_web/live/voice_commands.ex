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
      "Command not recognized. Try status, activity, AI calls, repo owner/name, task #42, or PR #42. Your draft is still here."
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
    label = if panel == "ai", do: "AI calls", else: "Activity"
    reply(:success, "Opened #{label} for #{slug(repo)}.", BoardNavigation.path(repo, panel))
  end

  defp select_repository(%{repos: repos}, requested) do
    case Enum.find(repos, &(normalize(slug(&1)) == requested)) do
      nil ->
        reply(
          :unknown,
          "Repository #{requested} is not tracked by this board. Your draft is still here."
        )

      repo ->
        reply(:success, "Selected #{slug(repo)}.", BoardNavigation.path(repo))
    end
  end

  defp find_task(%{repo: nil}, _number), do: missing_repository()

  defp find_task(%{repo: repo, sync_event: sync_event}, number) do
    case Board.find_task(repo, number) do
      nil ->
        reply(
          :unknown,
          "Task ##{number} is not in the saved data for #{slug(repo)}. #{sync_note(sync_event)} Your draft is still here."
        )

      task ->
        result = %{
          kind: :success,
          text:
            "Task ##{number}: #{task.title || "unknown"}. Saved state: #{task.state || "unknown"}. Updated #{timestamp(task.updated_at)}.",
          as_of: task.updated_at,
          source: "Task record updated"
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
          "PR ##{number} is not in the saved data for #{slug(repo)}. #{sync_note(sync_event)} Your draft is still here."
        )

      pr ->
        %{
          result: %{
            kind: :success,
            text:
              "PR ##{number}: #{pr.title || "unknown"}. Saved state: #{pr.state || "unknown"}. Updated #{timestamp(pr.updated_at)}.",
            as_of: pr.updated_at,
            source: "PR record updated",
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
      "Saved active lanes for #{slug(repo)}: #{counts.running} running, #{counts.ready} ready, " <>
        "#{counts.blocked} blocked, #{counts.queued} queued. #{sync_note(sync_event)}"

    reply(:success, text, nil, sync_time(sync_event), sync_source(sync_event))
  end

  defp blocked(%{repo: nil}), do: missing_repository()

  defp blocked(%{repo: repo, board: board, sync_event: sync_event}) do
    count = board.task_counts.blocked

    recent =
      board
      |> Map.get(:blocked, [])
      |> Enum.take(3)
      |> Enum.map_join(", ", &"##{&1.number || "unknown"} #{&1.title || "unknown"}")

    detail = if recent == "", do: "", else: " Recent blocked cards: #{recent}."

    text =
      "Saved board for #{slug(repo)}: #{count} blocked tasks.#{detail} #{sync_note(sync_event)}"

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
        text: "Ask task ##{task.number}: #{question}",
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
        "Choose a tracked repository before using this board command. Your draft is still here."
      )

  defp reply(kind, text, path \\ nil, as_of \\ nil, source \\ nil) do
    result = %{kind: kind, text: text, as_of: as_of}
    result = if source, do: Map.put(result, :source, source), else: result
    %{result: result, path: path}
  end

  defp sync_time(%{kind: "sync", inserted_at: at}), do: at
  defp sync_time(_), do: nil

  defp sync_source(%{kind: "sync"}), do: "Last completed sync"
  defp sync_source(_), do: nil

  defp sync_note(%{kind: "sync", inserted_at: at}),
    do: "Last completed sync: #{timestamp(at)}."

  defp sync_note(%{kind: "sync_error", inserted_at: at}),
    do: "Latest sync failed at #{timestamp(at)}; showing saved data of unknown age."

  defp sync_note(_), do: "No sync yet; saved data age is unknown."

  defp timestamp(nil), do: "unknown"
  defp timestamp(at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp safe_url("https://github.com/" <> _ = url), do: url
  defp safe_url(_), do: nil

  defp slug(repo), do: "#{repo.owner}/#{repo.name}"
end
