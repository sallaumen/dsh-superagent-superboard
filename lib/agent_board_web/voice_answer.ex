defmodule AgentBoardWeb.VoiceAnswer do
  @moduledoc """
  A bounded board snapshot for a registered natural-language answer.

  No board screen calls this module; it feeds the board AI evaluation
  (`scripts/eval-board-ai.exs`, see the maintainer contract). It never
  navigates, writes a task, or starts speech output.
  """

  alias AgentBoard.AI

  @sample_size 8
  @max_question_length 1_000
  @stale_after_seconds 300
  @task_lanes [:running, :ready, :blocked, :queued]
  @lane_terms [
    running: ~r/\b(?:running|rodando|execu[cç][aã]o|em andamento)\b/iu,
    ready: ~r/\b(?:ready|pront[oa]s?)\b/iu,
    blocked: ~r/\b(?:blocked|bloquead[oa]s?)\b/iu,
    queued: ~r/\b(?:queued|fila|enfileirad[oa]s?)\b/iu,
    merged: ~r/\b(?:merged|mesclad[oa]s?)\b/iu
  ]
  @task_lane_phrases [
    running:
      ~r/\b(?:running (?:tasks?|cards?|issues?)|tarefas? (?:rodando|em andamento|em execu[cç][aã]o))\b/iu,
    ready: ~r/\b(?:ready (?:tasks?|cards?|issues?)|tarefas? pront[ao]s?)\b/iu,
    blocked: ~r/\b(?:blocked (?:tasks?|cards?|issues?)|tarefas? bloquead[ao]s?)\b/iu,
    queued: ~r/\b(?:queued (?:tasks?|cards?|issues?)|tarefas? (?:na )?fila)\b/iu
  ]
  @coordinated_lanes [
    running:
      ~r/\b(?:(?:and|e) running (?:ones?|tasks?|cards?|issues?)|e (?:rodando|em andamento|em execu[cç][aã]o))\b/iu,
    ready: ~r/\b(?:(?:and|e) ready (?:ones?|tasks?|cards?|issues?)|e pront[ao]s?)\b/iu,
    blocked: ~r/\b(?:(?:and|e) blocked (?:ones?|tasks?|cards?|issues?)|e bloquead[ao]s?)\b/iu,
    queued: ~r/\b(?:(?:and|e) queued (?:ones?|tasks?|cards?|issues?)|e (?:na )?fila)\b/iu
  ]
  @merged_pull_phrase ~r/\b(?:merged (?:prs?|pull requests?)|(?:prs?|pull requests?) (?:are )?merged)\b/iu
  @task_terms ~r/\b(?:tasks?|tarefas?|cards?|issues?)\b/iu
  @pull_terms ~r/\b(?:prs?|pull requests?)\b/iu
  @title_question ~r/\b(?:titles?|t[ií]tulos?|names?|nomes?|(?:o que est[aá]|what is) (?:rodando|running|pronto|ready|bloqueado|blocked|na fila|queued)|(?:quais?|which) (?:tarefas?|tasks?|cards?|prs?|pull requests?))\b/iu
  @aggregate_question ~r/\b(?:how many|quantos?|quantas?|counts?|total|n[uú]mero de)\b/iu
  @archive_action ~r/\b(?:did (?:i|you|we|the agent|the board) archiv\w*|(?:i|you|we|was|were) archived|(?:voc[eê]|eu|o agente|o board|foi|foram) arquiv\w*)\b/iu
  @archive_inventory ~r/\b(?:archived tasks?|tasks? archived|tarefas? arquivad[ao]s?|arquivad[ao]s? tarefas?)\b/iu
  @archive_history_term ~r/\b(?:archive history|archiving history|archive actions?|hist[oó]rico (?:de |do |da )?arquiv\w*)\b/iu
  @read_starters [
    "o que",
    "o board",
    "o painel",
    "qual",
    "quais",
    "quantas",
    "quantos",
    "quem",
    "quando",
    "onde",
    "por que",
    "porque",
    "como",
    "me diga",
    "me conte",
    "explique",
    "resuma",
    "resumo",
    "status",
    "what",
    "which",
    "who",
    "when",
    "where",
    "why",
    "how",
    "tell me",
    "explain",
    "summarize"
  ]

  @doc "Whether the text asks to read or explain the saved board."
  def read_query?(text) when is_binary(text) do
    phrase =
      text
      |> String.trim()
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.trim_trailing("?")

    Enum.any?(@read_starters, fn starter ->
      phrase == starter or String.starts_with?(phrase, starter <> " ")
    end)
  end

  def read_query?(_text), do: false

  @doc "Whether a read question asks for archive history absent from the snapshot."
  def archive_history_query?(text) when is_binary(text) do
    (read_query?(text) or String.ends_with?(String.trim(text), "?")) and
      Enum.any?(
        [@archive_action, @archive_inventory, @archive_history_term],
        &Regex.match?(&1, text)
      )
  end

  def archive_history_query?(_text), do: false

  @spec answer(map(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def answer(snapshot, question) when is_map(snapshot) and is_binary(question) do
    with {:ok, repository} <- repository(snapshot),
         {:ok, question} <- question(question),
         {:ok, board} <- board(snapshot),
         :ok <- validate_lane_counts(board) do
      metadata = sync_metadata(Map.get(snapshot, :sync_event))
      answer_from_snapshot(repository, board, metadata, question)
    end
  end

  def answer(_snapshot, _question), do: {:error, :invalid_question}

  defp repository(%{repo: %{owner: owner, name: name}})
       when is_binary(owner) and is_binary(name),
       do: {:ok, "#{owner}/#{name}"}

  defp repository(_snapshot), do: {:error, :no_repository}

  defp question(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        {:error, :missing_question}

      String.length(trimmed) > @max_question_length ->
        {:error, :question_too_long}

      not read_query?(trimmed) and not archive_history_query?(trimmed) ->
        {:error, :not_read_query}

      true ->
        {:ok, trimmed}
    end
  end

  defp board(%{board: board}) when is_map(board), do: {:ok, board}
  defp board(_snapshot), do: {:error, :no_board_data}

  defp validate_lane_counts(board) do
    counts = Map.get(board, :task_counts) || %{}

    case Enum.all?(@task_lanes, &valid_lane_count?(board, counts, &1)) do
      true -> :ok
      false -> {:error, :inconsistent_board_data}
    end
  end

  defp valid_lane_count?(board, counts, lane) do
    rows = Map.get(board, lane) || []

    case Map.get(counts, lane) do
      nil -> is_list(rows)
      total when is_integer(total) and total >= 0 -> is_list(rows) and total >= length(rows)
      _other -> false
    end
  end

  defp title_question?(question) do
    Regex.match?(@title_question, question) and not Regex.match?(@aggregate_question, question)
  end

  defp title_targets(question) do
    if title_question?(question), do: mentioned_title_targets(question), else: []
  end

  defp mentioned_title_targets(question) do
    scope =
      question
      |> String.replace(
        ~r/(?:["“][^"”]*["”]|(?<![\p{L}\p{N}])'[^'\n]{1,120}'(?![\p{L}\p{N}]))/u,
        ""
      )
      |> String.replace(~r/\bto (?:be )?merged\b/iu, "")

    explicit = for {lane, pattern} <- @task_lane_phrases, Regex.match?(pattern, scope), do: lane

    explicit =
      if Regex.match?(@merged_pull_phrase, scope), do: explicit ++ [:merged], else: explicit

    coordinated =
      for {lane, pattern} <- @coordinated_lanes, Regex.match?(pattern, scope), do: lane

    explicit = Enum.uniq(explicit ++ coordinated ++ leading_task_lanes(scope))

    mentioned =
      if explicit == [],
        do: for({lane, pattern} <- @lane_terms, Regex.match?(pattern, scope), do: lane),
        else: explicit

    case mentioned do
      [] -> reference_title_targets(question)
      mentioned -> mentioned
    end
  end

  defp reference_title_targets(question) do
    targets = if Regex.match?(@task_terms, question), do: @task_lanes, else: []
    if Regex.match?(@pull_terms, question), do: targets ++ [:merged], else: targets
  end

  defp leading_task_lanes(scope) do
    case Regex.split(@task_terms, scope, parts: 2) do
      [prefix, _rest] ->
        for {lane, pattern} <- @lane_terms,
            lane in @task_lanes and Regex.match?(pattern, prefix),
            do: lane

      _other ->
        []
    end
  end

  defp answer_from_snapshot(repository, board, metadata, question) do
    if archive_history_query?(question) do
      text =
        if String.contains?(String.downcase(question), "arquiv") do
          "Os dados salvos do board não incluem histórico de arquivamento. Não consigo dizer o que foi arquivado ou quando."
        else
          "The saved board data does not include archive history. I cannot tell what was archived or when."
        end

      {:ok,
       %{
         as_of: nil,
         engine: :board,
         source: "Archive history unavailable",
         sync_status: :unknown,
         text: text
       }}
    else
      with {:ok, result} <-
             AI.call(:answer_board_question, %{
               question: question,
               board: facts(repository, board, metadata, title_targets(question))
             }),
           {:ok, text} <- answer_text(result) do
        {:ok, metadata |> Map.put(:text, text) |> Map.put(:engine, result.engine)}
      end
    end
  end

  defp facts(repository, board, metadata, title_targets) do
    %{
      repository: repository,
      sync: sync_facts(metadata),
      task_lanes: Map.new(@task_lanes, &{&1, task_lane(board, &1, &1 in title_targets)}),
      merged_pull_requests: merged_facts(board, :merged in title_targets)
    }
  end

  defp task_lane(board, lane, include_titles?) do
    rows = Map.get(board, lane) || []
    counts = Map.get(board, :task_counts) || %{}

    %{
      exact_total: Map.get(counts, lane),
      loaded_count: length(rows),
      sample: Enum.map(Enum.take(rows, @sample_size), &task_fact(&1, include_titles?))
    }
  end

  defp task_fact(task, include_titles?) do
    fact = %{
      number: Map.get(task, :number),
      kind: Map.get(task, :kind),
      updated_at: timestamp(Map.get(task, :updated_at))
    }

    if include_titles?, do: Map.put(fact, :title, Map.get(task, :title)), else: fact
  end

  defp merged_facts(board, include_titles?) do
    rows = Map.get(board, :merged) || []

    %{
      exact_total: nil,
      loaded_count: length(rows),
      has_more: Map.get(board, :merged_has_more),
      sample:
        Enum.map(Enum.take(rows, @sample_size), fn pull ->
          fact = %{
            number: Map.get(pull, :number),
            merged_at: timestamp(Map.get(pull, :merged_at))
          }

          if include_titles?, do: Map.put(fact, :title, Map.get(pull, :title)), else: fact
        end)
    }
  end

  defp sync_facts(metadata) do
    %{
      status: metadata.sync_status,
      last_successful_sync_at: timestamp(metadata.as_of),
      stale: stale?(Map.get(metadata, :sync_age_seconds)),
      failed_at: timestamp(Map.get(metadata, :sync_failed_at))
    }
  end

  defp stale?(nil), do: nil
  defp stale?(age_seconds), do: age_seconds >= @stale_after_seconds

  defp sync_metadata(%{kind: "sync", inserted_at: %DateTime{} = at}) do
    %{
      as_of: at,
      sync_age_seconds: max(DateTime.diff(DateTime.utc_now(), at), 0),
      sync_status: :synced,
      source: "Last completed sync"
    }
  end

  defp sync_metadata(%{kind: "sync"}),
    do: %{as_of: nil, sync_status: :synced, source: "Sync time unknown"}

  defp sync_metadata(%{kind: "sync_error", inserted_at: at}),
    do: %{
      as_of: nil,
      sync_status: :sync_failed,
      sync_failed_at: at,
      source: "Sync failed · showing saved data"
    }

  defp sync_metadata(_event),
    do: %{as_of: nil, sync_status: :unknown, source: "Sync time unknown"}

  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(_value), do: nil

  defp answer_text(%{json: %{"answer" => text}}) when is_binary(text) do
    case String.trim(text) do
      "" -> {:error, :empty_answer}
      answer -> {:ok, answer}
    end
  end

  defp answer_text(_result), do: {:error, :invalid_answer}
end
