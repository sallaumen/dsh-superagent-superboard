defmodule AgentBoardWeb.NumbersTest do
  use ExUnit.Case, async: true

  alias AgentBoardWeb.Numbers

  test "dollars follow the viewer's number format" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    assert Numbers.usd(2_653_120_000) == "US$ 2,653.12"
    assert Numbers.usd(19_280_000) == "US$ 19.28"
    assert Numbers.usd(2_653_120_000, cents: false) == "US$ 2,653"
    assert Numbers.usd_exact(171) == "US$ 0.000171"
    assert Numbers.grouped(2019) == "2,019"
    assert Numbers.decimal(1.1, 2) == "1.10"

    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
    assert Numbers.usd(2_653_120_000) == "US$ 2.653,12"
    assert Numbers.usd(19_280_000) == "US$ 19,28"
    assert Numbers.usd(2_653_120_000, cents: false) == "US$ 2.653"
    assert Numbers.usd_exact(171) == "US$ 0,000171"
    assert Numbers.grouped(2019) == "2.019"
    assert Numbers.decimal(1.1, 2) == "1,10"
  end

  test "an amount rounds to the cent and keeps both decimal places" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    assert Numbers.usd(0) == "US$ 0.00"
    assert Numbers.usd(4_999) == "US$ 0.00"
    assert Numbers.usd(5_000) == "US$ 0.01"
    assert Numbers.usd(999_995_000) == "US$ 1,000.00"
    assert Numbers.usd_exact(1_500_000) == "US$ 1.5"
    assert Numbers.usd_exact(2_000_000) == "US$ 2"
  end
end
