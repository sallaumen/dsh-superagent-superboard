defmodule AgentBoard.Conversation do
  @moduledoc """
  The owner's spoken conversation with the board's agent: its memory and the
  proposals waiting for a spoken yes.

  The memory is durable (`voice_turns`), so a reload or a second tab keeps the
  context. The model receives the latest `summary` turn plus the recent turns
  verbatim; when too many turns pile up after the summary, `compact/0` folds
  the oldest into a new summary (a registered AI call), so the context covers
  the whole chat without sending every word every time.

  The conversation never touches the coding agent: its only writes are the
  board actions a button would make (create a task, stop or archive one), and
  each of them waits for the owner's spoken confirmation.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.AI
  alias AgentBoard.Conversation.Turn
  alias AgentBoard.Repo

  @recent 16
  @compact_after 28
  @proposal_ttl_seconds 600
  @max_text 2_000

  @doc "Records a turn. Text is trimmed and capped."
  @spec record(String.t(), String.t(), keyword()) :: {:ok, Turn.t()} | {:error, term()}
  def record(role, text, opts \\ []) when is_binary(text) do
    %Turn{}
    |> Turn.changeset(%{
      role: role,
      text: text |> String.trim() |> String.slice(0, @max_text),
      repository_id: opts[:repository_id],
      action: opts[:action],
      proposal: opts[:proposal],
      proposal_status: if(opts[:proposal], do: "proposed"),
      duration_ms: opts[:duration_ms]
    })
    |> Repo.insert()
  end

  @doc """
  The context the model reads: the latest summary (or nil) and the turns
  after it, the most recent `@recent` verbatim, oldest first.
  """
  @spec context() :: %{summary: String.t() | nil, turns: [map()], earlier: non_neg_integer()}
  def context do
    summary = latest_summary()
    after_id = (summary && summary.summary_through_id) || 0

    turns =
      Repo.all(
        from t in Turn,
          where: t.role in ["owner", "agent"] and t.id > ^after_id,
          order_by: [desc: t.id],
          limit: @recent
      )
      |> Enum.reverse()

    %{
      summary: summary && summary.text,
      earlier: unsummarized_count(after_id) - length(turns),
      turns: Enum.map(turns, &turn_fact/1)
    }
  end

  @doc "The recent turns for the history view, oldest first."
  @spec recent(pos_integer()) :: [Turn.t()]
  def recent(limit \\ 12) do
    Repo.all(
      from t in Turn,
        where: t.role in ["owner", "agent"],
        order_by: [desc: t.id],
        limit: ^limit
    )
    |> Enum.reverse()
  end

  @doc "The proposal waiting for a yes, if it is recent enough; older ones expire."
  @spec pending_proposal(DateTime.t()) :: Turn.t() | nil
  def pending_proposal(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@proposal_ttl_seconds, :second)

    Repo.update_all(
      from(t in Turn, where: t.proposal_status == "proposed" and t.inserted_at < ^cutoff),
      set: [proposal_status: "expired"]
    )

    Repo.one(
      from t in Turn,
        where: t.proposal_status == "proposed",
        order_by: [desc: t.id],
        limit: 1
    )
  end

  @doc """
  Moves a proposal out of `proposed`, once. The update is conditional, so a
  repeated "sim" (a double event, a second tab) cannot claim it twice: only
  the first caller gets `:ok` and runs the effect.
  """
  @spec settle(Turn.t(), String.t()) :: :ok | :already_settled
  def settle(%Turn{id: id}, status) when status in ~w(confirmed cancelled expired) do
    case Repo.update_all(
           from(t in Turn, where: t.id == ^id and t.proposal_status == "proposed"),
           set: [proposal_status: status, updated_at: DateTime.utc_now()]
         ) do
      {1, _} -> :ok
      {0, _} -> :already_settled
    end
  end

  @doc "A new proposal replaces any older one still waiting."
  def supersede_proposals do
    Repo.update_all(
      from(t in Turn, where: t.proposal_status == "proposed"),
      set: [proposal_status: "expired"]
    )

    :ok
  end

  @doc "Forgets the whole conversation (the owner asked for a clean slate)."
  def clear do
    Repo.delete_all(Turn)
    :ok
  end

  @doc """
  Folds the oldest unsummarized turns into a new summary when too many piled
  up. Returns `:noop`, `{:ok, summary_turn}` or `{:error, reason}`; a failed
  summary keeps the turns as they are (nothing is lost, the context is only
  longer).
  """
  def compact do
    summary = latest_summary()
    after_id = (summary && summary.summary_through_id) || 0
    count = unsummarized_count(after_id)

    if count < @compact_after do
      :noop
    else
      fold =
        Repo.all(
          from t in Turn,
            where: t.role in ["owner", "agent"] and t.id > ^after_id,
            order_by: [asc: t.id],
            limit: ^(count - @recent)
        )

      inputs = %{previous_summary: summary && summary.text, turns: Enum.map(fold, &turn_fact/1)}

      with {:ok, %{json: %{"summary" => text}}} when is_binary(text) and text != "" <-
             AI.call(:summarize_conversation, inputs),
           {:ok, turn} <-
             %Turn{}
             |> Turn.changeset(%{
               role: "summary",
               text: String.slice(text, 0, 4_000),
               summary_through_id: List.last(fold).id
             })
             |> Repo.insert() do
        {:ok, turn}
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :invalid_summary}
      end
    end
  end

  defp latest_summary do
    Repo.one(from t in Turn, where: t.role == "summary", order_by: [desc: t.id], limit: 1)
  end

  defp unsummarized_count(after_id) do
    Repo.aggregate(
      from(t in Turn, where: t.role in ["owner", "agent"] and t.id > ^after_id),
      :count
    )
  end

  defp turn_fact(%Turn{} = turn) do
    %{role: turn.role, text: turn.text, at: DateTime.to_iso8601(turn.inserted_at)}
    |> then(fn fact -> if turn.action, do: Map.put(fact, :action, turn.action), else: fact end)
  end
end
