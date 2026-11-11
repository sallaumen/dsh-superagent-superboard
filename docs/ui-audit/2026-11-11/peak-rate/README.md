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

`peak-simulated-pt-light-1920.png` is the peak state made in the browser (the class and the icon the server renders in peak), since the capture ran off-peak; the server's peak rendering and the rule are covered by `peak_rate_test.exs`. Not observed: a real switch at the hour in a browser, and the owner's monitor.
