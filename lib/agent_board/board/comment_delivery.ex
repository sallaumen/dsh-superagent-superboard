defmodule AgentBoard.Board.CommentDelivery do
  @moduledoc """
  A send has one local receipt until GitHub supplies its comment id. A signed
  marker lets a mirror confirm that exact receipt if the sending tab disappears.
  Different GitHub ids always remain distinct, even if their text is identical.
  """
  import Ecto.Query
  alias AgentBoard.Board.Comment
  alias AgentBoard.Repo
  alias AgentBoardWeb.Endpoint

  @salt "board-comment-delivery-v1"
  @marker ~r/\A<!-- superboard-delivery:([A-Za-z0-9._-]+) -->\n\n/

  def mark(body, receipt) do
    token = Phoenix.Token.sign(Endpoint, @salt, {receipt.task_id, receipt.id})
    "<!-- superboard-delivery:#{token} -->\n\n" <> body
  end

  def unpack(task_id, %{"body" => body} = comment) when is_binary(body) do
    with [_, token] <- Regex.run(@marker, body),
         {:ok, {^task_id, id}} <- Phoenix.Token.verify(Endpoint, @salt, token, max_age: :infinity) do
      {Map.put(comment, "body", Regex.replace(@marker, body, "")), id}
    else
      _ -> {comment, nil}
    end
  end

  def unpack(_task_id, comment), do: {comment, nil}

  # No network access in this transaction. The acknowledgement and the mirror
  # can arrive in either order; only an identified local placeholder is removed.
  def store(attrs, receipt, source) do
    Repo.transact(fn ->
      conflict =
        if source == :ack, do: :nothing, else: {:replace, [:author, :body, :kind, :updated_at]}

      # Keep the send time if a slow acknowledgement arrives after other messages.
      sent_at = Repo.one(from c in pending(attrs.task_id, receipt), select: c.inserted_at)

      with {:ok, _} <-
             %Comment{inserted_at: sent_at}
             |> Comment.changeset(attrs)
             |> Repo.insert(on_conflict: conflict, conflict_target: [:task_id, :github_id]) do
        discard(attrs.task_id, receipt)
        {:ok, Repo.get_by!(Comment, task_id: attrs.task_id, github_id: attrs.github_id)}
      end
    end)
  end

  def discard(_task_id, nil), do: :ok

  def discard(task_id, receipt_id), do: Repo.delete_all(pending(task_id, receipt_id))

  defp pending(task_id, receipt_id) do
    from(c in Comment,
      where:
        c.task_id == ^task_id and c.id == ^receipt_id and c.github_id < 0 and c.author == "you"
    )
  end
end
