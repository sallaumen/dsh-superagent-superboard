defmodule AgentBoard.TimeTest do
  @moduledoc "The time phrases in both interface languages."
  use ExUnit.Case, async: true

  alias AgentBoard.Time

  @now ~U[2026-11-10 23:00:00Z]

  describe "in Portuguese" do
    setup do
      Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
      :ok
    end

    test "a relative phrase" do
      assert Time.ago(nil) == "desconhecido"
      assert Time.ago(30) == "há 30 s"
      assert Time.ago(7 * 60) == "há 7 min"
      assert Time.ago(2 * 3600) == "há 2 h"
      assert Time.ago(2 * 86_400) == "há 2 d"
    end

    test "since when, with the weekday in lower case" do
      assert Time.since_label(nil, 0, @now) == "antes da última visita"
      assert Time.since_label(~U[2026-11-10 22:10:00Z], 0, @now) == "hoje às 22:10"
      assert Time.since_label(~U[2026-11-09 22:10:00Z], 0, @now) == "ontem às 22:10"
      assert Time.since_label(~U[2026-11-04 22:10:00Z], 0, @now) == "quarta, 4 nov às 22:10"
    end

    test "a day heading starts with a capital" do
      assert Time.day_label(~D[2026-11-10], ~D[2026-11-10]) == "Hoje"
      assert Time.day_label(~D[2026-11-09], ~D[2026-11-10]) == "Ontem, 9 nov"
      assert Time.day_label(~D[2026-11-03], ~D[2026-11-10]) == "Terça, 3 nov"
      assert Time.short_day_label(~D[2026-11-10], ~D[2026-11-10]) == "hoje"
      assert Time.short_day_label(~D[2026-11-09], ~D[2026-11-10]) == "09"
      assert Time.weekday(~D[2026-11-07]) == "sábado"
      assert Time.month(~D[2026-03-01]) == "mar"
    end
  end

  describe "in English" do
    setup do
      Gettext.put_locale(AgentBoardWeb.Gettext, "en")
      :ok
    end

    test "a relative phrase" do
      assert Time.ago(nil) == "unknown"
      assert Time.ago(7 * 60) == "7 min ago"
    end

    test "since when, month before day" do
      assert Time.since_label(nil, 0, @now) == "before your last visit"
      assert Time.since_label(~U[2026-11-10 22:10:00Z], 0, @now) == "today at 22:10"
      assert Time.since_label(~U[2026-11-09 22:10:00Z], 0, @now) == "yesterday at 22:10"
      assert Time.since_label(~U[2026-11-04 22:10:00Z], 0, @now) == "Wednesday, 4 Nov at 22:10"
    end

    test "a day heading" do
      assert Time.day_label(~D[2026-11-10], ~D[2026-11-10]) == "Today"
      assert Time.day_label(~D[2026-11-09], ~D[2026-11-10]) == "Yesterday, 9 Nov"
      assert Time.day_label(~D[2026-11-03], ~D[2026-11-10]) == "Tuesday, 3 Nov"
      assert Time.short_day_label(~D[2026-11-10], ~D[2026-11-10]) == "today"
    end
  end
end
