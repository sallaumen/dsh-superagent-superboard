defmodule AgentBoardWeb.Numbers do
  @moduledoc """
  Numbers written the way the viewer's language writes them: "US$ 2,653.12"
  and "2,019" in English, "US$ 2.653,12" and "2.019" in Portuguese. Dollar
  amounts are microdollars, the unit the usage ledger stores.
  """

  @doc "Rounded to the cent; `cents: false` rounds to the dollar."
  def usd(micros, opts \\ []) when is_integer(micros) do
    cents = div(micros + 5_000, 10_000)
    {thousands, decimal} = separators()

    if Keyword.get(opts, :cents, true) do
      fraction = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
      "US$ " <> group(div(cents, 100), thousands) <> decimal <> fraction
    else
      "US$ " <> group(div(cents + 50, 100), thousands)
    end
  end

  @doc "Every stored digit, for costs far under a cent."
  def usd_exact(micros) when is_integer(micros) do
    {thousands, decimal} = separators()

    fraction =
      micros
      |> rem(1_000_000)
      |> Integer.to_string()
      |> String.pad_leading(6, "0")
      |> String.trim_trailing("0")

    whole = "US$ " <> group(div(micros, 1_000_000), thousands)
    if fraction == "", do: whole, else: whole <> decimal <> fraction
  end

  @doc "A number with `places` decimal places and the viewer's decimal mark."
  def decimal(value, places) when is_number(value) do
    {_thousands, mark} = separators()
    value |> Kernel./(1) |> :erlang.float_to_binary(decimals: places) |> String.replace(".", mark)
  end

  @doc ~S(A file size: "820 KB", "12,4 MB", "19,3 GB".)
  def bytes(bytes) when is_integer(bytes) and bytes < 1_000_000,
    do: "#{max(div(bytes + 999, 1000), 0)} KB"

  def bytes(bytes) when is_integer(bytes) and bytes < 1_000_000_000,
    do: decimal(bytes / 1_000_000, 1) <> " MB"

  def bytes(bytes) when is_integer(bytes), do: decimal(bytes / 1_000_000_000, 1) <> " GB"

  @doc "A whole number with its thousands separated."
  def grouped(integer) when is_integer(integer), do: group(integer, elem(separators(), 0))

  defp group(integer, separator) do
    integer
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1" <> separator)
    |> String.reverse()
  end

  defp separators do
    if Gettext.get_locale(AgentBoardWeb.Gettext) == "pt_BR", do: {".", ","}, else: {",", "."}
  end
end
