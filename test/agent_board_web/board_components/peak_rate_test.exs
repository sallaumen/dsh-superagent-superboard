defmodule AgentBoardWeb.BoardComponents.PeakRateTest do
  @moduledoc "DeepSeek's peak hours as the owner reads them: the rate now, the next change, the local day."
  use ExUnit.Case, async: true

  alias AgentBoard.AI.Providers
  alias AgentBoardWeb.BoardComponents.PeakRate

  # Brasília: three hours behind UTC, as the browser reports it.
  @brt 180

  test "the rate changes on the next whole UTC hour across the boundary" do
    assert Providers.next_rate_change(~U[2026-11-10 07:20:00Z]) == ~U[2026-11-10 10:00:00Z]
    assert Providers.next_rate_change(~U[2026-11-10 04:30:00Z]) == ~U[2026-11-10 06:00:00Z]
    assert Providers.next_rate_change(~U[2026-11-10 00:59:59Z]) == ~U[2026-11-10 01:00:00Z]
    # Friday's last peak ends; the next starts on Monday at 01:00 UTC
    assert Providers.next_rate_change(~U[2026-11-13 09:00:00Z]) == ~U[2026-11-13 10:00:00Z]
    assert Providers.next_rate_change(~U[2026-11-14 12:00:00Z]) == ~U[2026-11-16 01:00:00Z]
  end

  test "the owner's day shows its peak windows in local time" do
    # Tuesday 10 Nov at 12:00 in Brasília
    tuesday = PeakRate.info(~U[2026-11-10 15:00:00Z], @brt)
    refute tuesday.peak?
    assert tuesday.until == ~U[2026-11-11 01:00:00Z]
    assert tuesday.windows == [{0, 4}, {12, 28}, {88, 96}]
    assert tuesday.now_quarter == 48

    assert PeakRate.windows_text(tuesday.windows) ==
             "Peak today: 00:00–01:00, 03:00–07:00, 22:00–24:00"

    # Friday: no evening window, Saturday in UTC has no peak
    assert PeakRate.info(~U[2026-11-13 15:00:00Z], @brt).windows == [{0, 4}, {12, 28}]
    # Sunday evening is already Monday in UTC
    assert PeakRate.info(~U[2026-11-15 15:00:00Z], @brt).windows == [{88, 96}]
    # Saturday: none
    assert PeakRate.info(~U[2026-11-14 15:00:00Z], @brt).windows == []
    assert PeakRate.windows_text([]) == "No peak hours today."
  end

  test "inside a window it is peak until the window ends" do
    rate = PeakRate.info(~U[2026-11-10 07:00:00Z], @brt)
    assert rate.peak?
    assert rate.until == ~U[2026-11-10 10:00:00Z]
    assert PeakRate.ms_until_change(rate, ~U[2026-11-10 07:00:00Z]) == 3 * 3_600_000
  end
end
