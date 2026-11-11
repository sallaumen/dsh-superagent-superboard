defmodule AgentBoardWeb.BoardComponents.PeakRate do
  @moduledoc """
  DeepSeek's peak hours, beside Messages and Attention: a flame while the
  full price runs, a moon while every token costs half (`Providers.peak?/1`).
  Opened, it shows the owner's day with its peak windows and when the rate
  changes next. A timer on the page re-reads it at that moment.
  """
  use AgentBoardWeb, :html

  alias AgentBoard.AI.Providers
  alias AgentBoardWeb.Time

  @quarters 96

  @type t :: %{
          peak?: boolean(),
          until: DateTime.t(),
          windows: [{non_neg_integer(), pos_integer()}],
          now_quarter: non_neg_integer()
        }

  @doc """
  The rate now and the owner's local day: its peak windows as
  `{first_quarter, end_quarter}` (quarters of an hour from local midnight)
  and the quarter the clock is in.
  """
  @spec info(DateTime.t(), integer()) :: t()
  def info(%DateTime{} = now, offset) do
    midnight =
      now
      |> Time.local_date(offset)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      |> DateTime.add(offset * 60, :second)

    windows =
      0..(@quarters - 1)
      |> Enum.filter(&Providers.peak?(DateTime.add(midnight, &1 * 900, :second)))
      |> Enum.chunk_while(nil, &chunk/2, &finish/1)

    %{
      peak?: Providers.peak?(now),
      until: Providers.next_rate_change(now),
      windows: windows,
      now_quarter: min(div(DateTime.diff(now, midnight), 900), @quarters - 1)
    }
  end

  defp chunk(quarter, {first, last}) when quarter == last, do: {:cont, {first, quarter + 1}}
  defp chunk(quarter, nil), do: {:cont, {quarter, quarter + 1}}
  defp chunk(quarter, window), do: {:cont, window, {quarter, quarter + 1}}

  defp finish(nil), do: {:cont, nil}
  defp finish(window), do: {:cont, window, nil}

  @doc "Milliseconds until the rate changes, at least one."
  @spec ms_until_change(t(), DateTime.t()) :: pos_integer()
  def ms_until_change(%{until: until}, now), do: max(DateTime.diff(until, now, :millisecond), 1)

  attr :rate, :map, required: true
  attr :offset, :integer, required: true
  attr :now, :any, required: true

  def mark(assigns) do
    assigns = assign(assigns, :until_text, until_text(assigns.rate, assigns.now, assigns.offset))

    ~H"""
    <details
      id="peak-rate"
      class={["ab-hub-menu ab-peak", @rate.peak? && "is-peak"]}
      data-board-menu
      phx-hook="BoardMenu"
    >
      <summary aria-label={summary_text(@rate, @until_text)} title={summary_text(@rate, @until_text)}>
        <span class="ab-peak__glyph" aria-hidden="true">
          <.icon name={if @rate.peak?, do: "hero-fire", else: "hero-moon"} class="size-5" />
        </span>
      </summary>
      <div class="ab-hub-menu__popover ab-peak__popover">
        <header class="ab-hub-menu__heading">
          <div>
            <strong>{gettext("DeepSeek's peak hours")}</strong>
            <p>{gettext("What a token costs at this hour")}</p>
          </div>
          <span class={["ab-peak__now", @rate.peak? && "is-peak"]} role="status">
            {if @rate.peak?, do: gettext("Peak now"), else: gettext("Off-peak now")}
          </span>
        </header>
        <div class="ab-peak__body">
          <p class="ab-peak__line">
            <%= if @rate.peak? do %>
              {gettext("Full price until %{time}. Off-peak, every token costs half.",
                time: @until_text
              )}
            <% else %>
              {gettext("Half price until %{time}: a good time to start long tasks.",
                time: @until_text
              )}
            <% end %>
          </p>
          <figure class="ab-peak__day">
            <figcaption>{gettext("Today, in your time")}</figcaption>
            <svg viewBox="0 0 96 8" preserveAspectRatio="none" aria-hidden="true">
              <rect class="ab-peak__track" x="0" y="0" width="96" height="8" rx="1.5" />
              <rect
                :for={{first, last} <- @rate.windows}
                class="ab-peak__window"
                x={first}
                y="0"
                width={last - first}
                height="8"
              />
              <rect class="ab-peak__clock" x={@rate.now_quarter} y="-1" width="0.6" height="10" />
            </svg>
            <div class="ab-peak__hours" aria-hidden="true">
              <span>00</span><span>06</span><span>12</span><span>18</span><span>24</span>
            </div>
            <p class="ab-peak__windows">{windows_text(@rate.windows)}</p>
          </figure>
        </div>
        <p class="ab-hub-menu__foot">
          {gettext(
            "DeepSeek's published rates, read on 10 Nov 2026: peak from 01:00 to 04:00 and 06:00 to 10:00 UTC, Monday to Friday in UTC. Chinese public holidays are off-peak too; the board has no such calendar and shows them as peak."
          )}
        </p>
      </div>
    </details>
    """
  end

  defp summary_text(%{peak?: true}, until),
    do: gettext("DeepSeek peak hours: full price until %{time}", time: until)

  defp summary_text(_rate, until),
    do: gettext("DeepSeek off-peak: half price until %{time}", time: until)

  # The time alone today; the weekday when the change is on another day.
  defp until_text(%{until: until}, now, offset) do
    time = Time.local_time(until, offset)

    if Time.local_date(until, offset) == Time.local_date(now, offset),
      do: time,
      else:
        gettext("%{day} %{time}", day: Time.weekday(Time.local_date(until, offset)), time: time)
  end

  @doc false
  def windows_text([]), do: gettext("No peak hours today.")

  def windows_text(windows) do
    gettext("Peak today: %{windows}",
      windows:
        Enum.map_join(windows, ", ", fn {first, last} -> "#{clock(first)}–#{clock(last)}" end)
    )
  end

  defp clock(quarter) do
    hours = div(quarter, 4) |> Integer.to_string() |> String.pad_leading(2, "0")
    minutes = (rem(quarter, 4) * 15) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{hours}:#{minutes}"
  end
end
