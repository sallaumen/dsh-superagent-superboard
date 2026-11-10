defmodule AgentBoard.System.Version do
  @moduledoc """
  What this node is running against what main has.

  The served sha is read once and cached: code cannot change under a running
  node, so the answer stays true for the life of the process. The available
  sha needs the network, so `refresh/0` is explicit: the panel calls it when
  it opens, and an open board rechecks every five minutes. The check is a
  fetch, never an automatic update.
  """

  alias AgentBoard.System.Git

  @served :agent_board_served_sha
  @available :agent_board_available
  @fetched_at :agent_board_fetched_at
  # Under the tabs' five-minute tick, so one of them still fetches every round.
  @shared_fetch_ms 4 * 60 * 1000

  @type status :: %{
          served: String.t() | nil,
          available: String.t() | nil,
          behind: non_neg_integer() | nil,
          dirty: boolean(),
          commits: [map()],
          state: :up_to_date | :behind | :restart | :ahead | :unknown
        }

  @doc "The sha this node booted with (nil when git is unavailable)."
  @spec served() :: String.t() | nil
  def served do
    case :persistent_term.get(@served, nil) do
      nil ->
        sha =
          case Git.head() do
            {:ok, sha} -> sha
            {:error, _} -> nil
          end

        :persistent_term.put(@served, sha)
        sha

      sha ->
        sha
    end
  end

  @doc "Fetches origin/main and records what it found. The only network read."
  @spec refresh() :: {:ok, String.t() | nil} | {:error, term()}
  def refresh do
    case Git.fetch() do
      :ok ->
        available =
          case Git.origin_main() do
            {:ok, sha} -> sha
            {:error, _} -> nil
          end

        :persistent_term.put(@available, available)
        {:ok, available}

      error ->
        error
    end
  end

  @doc """
  `refresh/0` for the periodic check of every open tab. After the Mac wakes
  they all ask at once, and git allows one ref update at a time: one fetches,
  the others keep the last answer.
  """
  @spec refresh_shared((-> {:ok, String.t() | nil} | {:error, term()})) ::
          {:ok, String.t() | nil} | {:error, term()}
  def refresh_shared(fetch \\ &refresh/0) do
    case :global.trans({__MODULE__, self()}, fn -> fetch_unless_recent(fetch) end, [node()], 0) do
      :aborted -> {:ok, available()}
      result -> result
    end
  end

  defp fetch_unless_recent(fetch) do
    now = System.monotonic_time(:millisecond)
    last = :persistent_term.get(@fetched_at, nil)

    if last && now - last < @shared_fetch_ms do
      {:ok, available()}
    else
      with {:ok, _sha} = fetched <- fetch.() do
        :persistent_term.put(@fetched_at, now)
        fetched
      end
    end
  end

  @doc "The last fetched available sha, without touching the network."
  @spec available() :: String.t() | nil
  def available, do: :persistent_term.get(@available, nil)

  @doc "The full picture the panel renders."
  @spec status() :: status()
  def status do
    served = served()
    available = available()

    behind =
      case Git.behind() do
        {:ok, count} -> count
        {:error, _} -> nil
      end

    commits =
      case Git.commits(served, available) do
        {:ok, commits} -> commits
        {:error, _reason} -> []
      end

    %{
      served: served,
      available: available,
      behind: behind,
      dirty: Git.dirty?(),
      commits: commits,
      state: state(served, available, behind)
    }
  end

  @doc false
  def state(nil, _available, _behind), do: :unknown
  def state(_served, nil, _behind), do: :unknown
  def state(served, served, _behind), do: :up_to_date
  def state(_served, _available, behind) when is_integer(behind) and behind > 0, do: :behind

  # The checkout is already on main, but this VM still serves the old sha:
  # the fast-forward happened and the restart did not. Say so instead of
  # claiming "up to date" from HEAD alone.
  def state(served, available, 0) when served != available, do: :restart
  def state(_served, _available, 0), do: :up_to_date
  def state(_served, _available, _behind), do: :unknown
end
