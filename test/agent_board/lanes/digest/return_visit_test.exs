defmodule AgentBoard.Lanes.Digest.ReturnVisitTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Digest.{ReturnVisit, Visit}
  @now ~U[2026-11-16 12:00:00Z]
  @previous ~U[2026-11-16 00:30:00Z]
  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  defp build(facts, opts) do
    visit = Visit.from_options([now: @now, last_visit: @previous, tz_offset: 180] ++ opts)
    ReturnVisit.build(facts, nil, visit)
  end

  test "with no changes, a live return is quiet but an unconfirmed sync is unknown" do
    live = build([], [])

    assert live == %{
             prefix: "Since yesterday at 21:30 ",
             segments: [%{text: "nothing changed", role: :plain}],
             suffix: ".",
             now: @now
           }

    assert build([], frozen: true) == %{
             live
             | prefix: "Without a completed sync, ",
               segments: [%{text: "we do not know what changed", role: :plain}]
           }
  end

  test "a saved sync bounds what can be said, including when the known interval was quiet" do
    stopped = [frozen_at: ~U[2026-11-16 11:15:00Z]]
    digest = build([merged: 2], stopped)

    assert digest == %{
             prefix: "Until 08:15, ",
             segments: [%{text: "the agent merged 2 PRs", role: :agent}],
             suffix: ". After that, we do not know.",
             now: @now
           }

    assert build([], stopped) == %{digest | segments: [%{text: "nothing changed", role: :plain}]}
  end
end
