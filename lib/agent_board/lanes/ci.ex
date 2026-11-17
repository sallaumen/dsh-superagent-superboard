defmodule AgentBoard.Lanes.CI do
  @moduledoc "What the board can conclude from a local gate and the mirrored remote checks."

  alias AgentBoard.Board.PullRequest

  @type verdict ::
          {:pass, :local_pass | :remote_pass}
          | {:fail, :local_fail}
          | {:unknown, :stale | :remote_failure | :pending | :no_checks | :incomplete}

  @doc "Local evidence takes precedence. A gate for another head stays unknown even with green remote checks."
  @spec classify(PullRequest.t(), map() | nil) :: verdict()
  def classify(_pull, %{state: :pass}), do: {:pass, :local_pass}
  def classify(_pull, %{state: :fail, detail: _}), do: {:fail, :local_fail}
  def classify(_pull, %{state: :stale, detail: _}), do: {:unknown, :stale}
  def classify(_pull, %{state: :unknown, detail: _}), do: {:unknown, :incomplete}
  def classify(%PullRequest{checks_state: "failure"}, nil), do: {:unknown, :remote_failure}
  def classify(%PullRequest{checks_state: "success"}, nil), do: {:pass, :remote_pass}
  def classify(%PullRequest{checks_state: "pending"}, nil), do: {:unknown, :pending}
  def classify(_pull, nil), do: {:unknown, :no_checks}

  @doc "Only an observed pass or failure counts as a local result for a row or a day's totals."
  @spec local_result(map() | nil) :: :pass | :fail | nil
  def local_result(%{state: result}) when result in [:pass, :fail], do: result
  def local_result(_), do: nil
end
