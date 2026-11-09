defmodule AgentBoard.AgentAccess.Refusals do
  @moduledoc """
  The mentions a superagent refused because their author is not cleared,
  read from its own database. The management API lists decisions without
  their author, so this reads the tables the way `AgentBoard.AgentState`
  does; the file is opened read-only and the board never writes it.

  Only a person who addressed the bot counts. The agent also records
  `not_a_member` for issues that never mentioned it, and those are not
  requests.
  """

  @limit 500

  @query """
  SELECT t.id,
         t.at,
         json_extract(t.value, '$.actor.id'),
         json_extract(t.value, '$.meta.number'),
         json_extract(t.value, '$.url'),
         (SELECT json_extract(th.value, '$.meta.title') FROM thread th WHERE th.key = d.thread),
         EXISTS (
           SELECT 1 FROM decision later
           WHERE later.thread = d.thread
             AND json_extract(later.value, '$.kind') = 'accept'
             AND json_extract(later.value, '$.at') > json_extract(d.value, '$.at')
         )
  FROM decision d, json_each(d.value, '$.reason') reason
  JOIN trigger t ON t.id = json_extract(reason.value, '$.triggerId')
  WHERE json_extract(d.value, '$.kind') = 'ignore'
    AND json_extract(reason.value, '$.code') = 'not_a_member'
    AND json_extract(t.value, '$.human') = 1
    AND json_extract(t.value, '$.source') = 'github'
    AND json_extract(t.value, '$.addressed') IS NOT NULL
  ORDER BY t.at DESC
  LIMIT #{@limit}
  """

  @type refusal :: %{
          trigger_id: String.t(),
          at: DateTime.t(),
          login: String.t(),
          number: pos_integer() | nil,
          url: String.t() | nil,
          title: String.t() | nil,
          handled: boolean()
        }

  @doc "The refused mentions in a state directory, newest first."
  @spec read(String.t()) :: {:ok, [refusal()]} | {:error, term()}
  def read(state_dir) when is_binary(state_dir) do
    path = Path.join(state_dir, "orchestrator.sqlite")

    with {:ok, conn} <- Exqlite.Sqlite3.open(path, mode: :readonly) do
      try do
        with {:ok, statement} <- Exqlite.Sqlite3.prepare(conn, @query),
             {:ok, rows} <- Exqlite.Sqlite3.fetch_all(conn, statement) do
          Exqlite.Sqlite3.release(conn, statement)
          {:ok, rows |> Enum.flat_map(&refusal/1) |> Enum.uniq_by(& &1.trigger_id)}
        end
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  defp refusal([trigger_id, at, login, number, url, title, handled]) do
    case DateTime.from_iso8601(to_string(at)) do
      {:ok, at, _offset} when is_binary(login) ->
        [
          %{
            trigger_id: trigger_id,
            at: DateTime.truncate(at, :second),
            login: login,
            number: AgentBoard.GitHub.number(number),
            url: url,
            title: title,
            handled: handled == 1
          }
        ]

      _malformed ->
        []
    end
  end
end
