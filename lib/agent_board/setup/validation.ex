defmodule AgentBoard.Setup.Validation do
  @moduledoc """
  The two most recent setup receipts: a successful check and one with issues.
  Each completed manual check replaces just its own outcome. Only UTC time
  and counts are stored; no provider output, account or credential is kept.
  """

  alias AgentBoard.{Settings, Setup}

  @passed "setup_check_passed"
  @issues "setup_check_issues"
  @type receipt :: %{at: DateTime.t(), passed?: boolean(), counts: %{String.t() => integer()}}
  @type history :: %{latest: receipt() | nil, passed: receipt() | nil}

  @doc "Read the last outcomes without contacting any provider."
  @spec history() :: history()
  def history do
    passed = read(@passed)
    issues = read(@issues)
    %{latest: latest(passed, issues), passed: passed}
  end

  @doc "Prepare the bounded receipt for the registered check_setup action to store."
  @spec receipt([Setup.row()]) :: {String.t(), String.t()}
  def receipt(rows) do
    counts = Enum.frequencies_by(rows, &Atom.to_string(&1.state))
    passed? = Enum.all?(rows, &(&1.state == :ok or (&1.state == :off and not &1.required)))
    key = if passed?, do: @passed, else: @issues
    {key, Jason.encode!(%{at: DateTime.to_iso8601(DateTime.utc_now()), counts: counts})}
  end

  defp read(key) do
    with value when is_binary(value) <- Settings.get(key),
         {:ok, %{"at" => iso, "counts" => counts}} when is_map(counts) and is_binary(iso) <-
           Jason.decode(value),
         {:ok, at, _offset} <- DateTime.from_iso8601(iso),
         true <- Enum.all?(counts, fn {_state, count} -> is_integer(count) and count >= 0 end) do
      %{at: at, counts: counts, passed?: key == @passed}
    else
      _invalid -> nil
    end
  end

  defp latest(nil, issues), do: issues
  defp latest(passed, nil), do: passed

  defp latest(passed, issues),
    do: if(DateTime.after?(passed.at, issues.at), do: passed, else: issues)
end
