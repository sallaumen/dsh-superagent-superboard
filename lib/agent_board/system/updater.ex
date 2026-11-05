defmodule AgentBoard.System.Updater do
  @moduledoc """
  Fast-forwards this checkout to origin/main, only when a person asks.

  Nothing here runs on a timer. The board watches agents, and an automatic
  restart would interrupt them -- which is why this is a button and not a
  cron. `pull/0` never merges or rebases: a diverged branch is an error the
  person resolves, not something the panel hides.
  """

  alias AgentBoard.System.Git

  @type result :: {:ok, String.t() | nil} | {:error, term()}

  @doc "Fetches origin/main and fast-forwards HEAD to it."
  @spec pull() :: result()
  def pull do
    with :ok <- Git.fetch(),
         {:ok, _output} <- fast_forward() do
      Git.head()
    end
  end

  defp fast_forward do
    case Git.run(["merge", "--ff-only", "origin/main"]) do
      {:ok, output} -> {:ok, output}
      error -> error
    end
  end
end
