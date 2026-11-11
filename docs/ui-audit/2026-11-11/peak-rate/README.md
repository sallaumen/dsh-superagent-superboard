# DeepSeek's peak hours on the board

The owner asked for a discreet mark that says when DeepSeek charges its full price, so tasks can go out off-peak.

- **Where.** First in the row of Messages and Attention, an icon alone: a flame in the stale amber while the full price runs, a moon in faint ink while every token costs half. Hover says it in one sentence ("Fora do pico da DeepSeek: metade do preço até 22:00"); click or Enter opens the day.
- **Opened.** The rate now, when it changes, and a bar of the owner's day in local time with the peak windows and a mark for now, then the windows as text and where the rule comes from, with its limit: Chinese public holidays are off-peak and the board shows them as peak.
- **Motion.** While peak, the flame flickers slowly from its base (2.6 s, `--ease-standard`); it is real state, like the attention dot. Off-peak nothing moves. Under reduced motion the flame is still. The switch is a cut at the hour, set by the page's one server timer.
- **No images.** The icons are the board's Heroicons, so they follow the theme; no generated image was needed.

Measured in WebKit on an isolated server with a copy of the data, 2026-11-11 at about 09:40 in Brasília (off-peak):

| Case | Result |
|---|---|
| 1920, English, dark | mark 42 × 44 px, 6 px from Messages; popover inside the window |
| 1920, Portuguese, light | same, Portuguese text |
| 375, Portuguese, dark | popover 343 px wide, 16 px from each edge, no horizontal overflow |
| Peak, no-preference | 1 animation on the flame |
| Peak, reduced motion | 0 animations |

`peak-simulated-pt-light-1920.png` is the peak state made in the browser (the class and the icon the server renders in peak), since the capture ran off-peak; the rule and both renderings (flame and moon) are covered by `peak_rate_test.exs`. Not observed: a real switch at the hour in a browser, and the owner's monitor.

## The window under the bar (#602 review)

The first version anchored the opened window to the mark, so it opened leftward from it. Between the phone rule and a 700 px window it left the screen: its left edge was at −212 px at 481, −93 at 600 and −1 at 700. It now aligns with the bar's right edge like Messages and Attention: left edge 45 px at 481, 164 at 600, 256 at 700, inside at 375, 768, 1280 and 1920 (`open-pt-light-600.png`). Measured in WebKit on an isolated server.
