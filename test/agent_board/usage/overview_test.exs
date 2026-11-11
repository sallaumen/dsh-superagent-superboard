defmodule AgentBoard.Usage.OverviewTest do
  @moduledoc "Settings → Costs → Summary: each source in its own currency, a missing price never zero."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.AI.Call
  alias AgentBoard.Usage.Overview
  alias AgentBoardWeb.BoardComponents.Settings.Costs

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "total/1: nothing priced is unknown, a missing price makes a minimum" do
    assert Overview.total([]) == nil
    assert Overview.total([nil]) == nil
    assert Overview.total([%{micros: 5, complete?: true}, nil]) == %{micros: 5, complete?: false}

    assert Overview.total([%{micros: 5, complete?: true}, %{micros: 2, complete?: true}]) ==
             %{micros: 7, complete?: true}
  end

  test "a board call with tokens and no price makes the board's total a minimum" do
    call(%{status: "ok", input_tokens: 100, output_tokens: 50, cost_micros: 30_000})
    call(%{status: "ok", input_tokens: 100, output_tokens: 50, cost_micros: 0})
    call(%{status: "error", error: "timeout"})

    overview = Overview.build(7)

    assert overview.board_ai == %{
             calls: 3,
             errors: 1,
             cost: %{micros: 30_000, complete?: false}
           }

    tile = Enum.find(Costs.tiles(overview, DateTime.utc_now(), 0), &(&1.key == "board"))
    assert tile.value == "≥ US$ 0.03"
    assert tile.fact == "3 calls · 1 with an error"
  end

  test "a source that did not run says so, an unpriced day is unknown, Codex unread is ?" do
    ledger(%{model: "a-model-without-price"})

    overview = Overview.build(7)
    tiles = Map.new(Costs.tiles(overview, DateTime.utc_now(), 0), &{&1.key, &1})

    assert tiles["agent"].value == "?"
    assert tiles["claude"].value == "—"
    assert tiles["codex"].value == "?"
    assert tiles["voice"].value == "—"

    today = Enum.find(overview.series, &(&1.day == Date.utc_today()))
    assert today.agent == nil
    assert %{bars: bars} = Costs.chart(overview)
    assert List.last(bars).unknown?
  end

  test "the voice window sums its days and leaves the older ones out" do
    voice(Date.utc_today(), 120, 2)
    voice(Date.add(Date.utc_today(), -2), 80, 1)
    voice(Date.add(Date.utc_today(), -30), 999, 9)

    assert %{tts_characters: 200, cache_hits: 3, days: 2} = Overview.build(7).voice
  end

  # The peak rate is double the off-peak one: the same tokens at 02:30 and at
  # 12:30 UTC of a weekday put two thirds of the cost in the peak.
  test "the agent's tile says how much of its DeepSeek cost paid the peak rate" do
    day =
      1..7
      |> Enum.map(&Date.add(Date.utc_today(), -&1))
      |> Enum.find(&(Date.day_of_week(&1) in 1..5))

    message(DateTime.new!(day, ~T[02:30:00], "Etc/UTC"), "m-1")
    message(DateTime.new!(day, ~T[12:30:00], "Etc/UTC"), "m-2")

    assert %{share: share} = Overview.build(7).peak
    assert_in_delta share, 2 / 3, 0.001
  end

  test "select/3 narrows by executor and project; outside is the sessions with no project" do
    runs = [
      %{source: "dsh", project: "arena-rogue"},
      %{source: "claude_code", project: "arena-rogue"},
      %{source: "codex", project: nil}
    ]

    assert length(Overview.select(runs, "all", "all")) == 3
    assert [%{source: "dsh"}] = Overview.select(runs, "dsh", "arena-rogue")
    assert [%{source: "codex"}] = Overview.select(runs, "all", "outside")
    assert Overview.select(runs, "codex", "arena-rogue") == []
  end

  defp call(attrs) do
    %Call{}
    |> Call.changeset(Map.merge(%{name: "refine_request", engine: "deepseek"}, attrs))
    |> Repo.insert!()
  end

  defp ledger(attrs) do
    at = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("usage_ledger", [
      Map.merge(
        %{
          source: "dsh",
          execution_id: "ticket-1",
          day: Date.utc_today(),
          cwd: "/tmp/overview",
          requests: 1,
          input_tokens: 1_000,
          output_tokens: 1_000,
          cache_read_tokens: 0,
          cache_write_tokens: 0,
          first_at: at,
          last_at: at,
          inserted_at: at,
          updated_at: at
        },
        attrs
      )
    ])
  end

  defp voice(day, characters, hits) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("eleven_labs_usage", [
      %{
        day: day,
        tts_characters: characters,
        tts_requests: 1,
        cache_hits: hits,
        stt_seconds: 0.0,
        stt_requests: 0,
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  defp message(at, id) do
    Repo.insert_all("usage_messages", [
      %{
        source: "dsh",
        message_id: id,
        execution_id: "ticket-1",
        at: DateTime.to_naive(at),
        day: DateTime.to_date(at),
        model: "deepseek-flash",
        input_tokens: 1_000_000,
        output_tokens: 0,
        cache_read_tokens: 0,
        cache_write_tokens: 0,
        cache_write_1h_tokens: 0
      }
    ])
  end
end
