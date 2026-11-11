# Interface motion

The board's motion contract: what animates, with which curve and duration, and
what never animates. The shared practice lives in the Elixir Agent Kit
(`motion-design` and `MOTION.md`, via [.elixir-agent-kit/START.md](../.elixir-agent-kit/START.md));
this document keeps only this product's decisions.

Rendered video, motion graphics and presentations do not follow this contract:
they use the external `motion-designer` skill (motion-kit, MIT) pointed to by the
kit's routing guide.

## Rule

Motion responds to a state change. It explains where a new surface came from,
confirms that an entry was received and shows that something left. It never
blocks an action, never replays broadcast data and never suggests work that did
not happen.

The board is an operational instrument: the record is technical and editorial —
precise, short, without spectacle. At most one expressive moment per screen, and
no showcase effect.

## Tokens

Durations and curves exist in one place: in the `:root` block of
[`assets/css/app.css`](../assets/css/app.css). Components use the token, not the
number.

| Token | Value | Use |
|---|---|---|
| `--motion-feedback` | 110 ms | Color of hover, focus and the button and link state |
| `--motion-inplace` | 160 ms | Change in place, such as the rotation of a chevron |
| `--motion-enter` | 200 ms | Entry of a new surface: panel, menu, notice |
| `--motion-notice` | 600 ms | Value that changed in place: the ink goes from `--agent` to `--ink` |
| `--ease-standard` | `cubic-bezier(0.2, 0, 0.38, 0.9)` | Utility (Carbon productive standard) |
| `--ease-enter` | `cubic-bezier(0.05, 0.7, 0.1, 1)` | Entry that matters (Material 3 emphasized decelerate) |

Exits are an immediate cut. When an animated exit exists, it will be shorter than
the entry and accelerate outward; the token will be created when the case
exists, not before.

## What moves

| Change | Treatment | Surface |
|---|---|---|
| Opening a panel or dialog | 200 ms, opacity + 6 px + scale 0.995, `--ease-enter` | `.board-dialog[open]` |
| Temporary notice (toast) | 200 ms, opacity + 4 px, `--ease-enter` | `.toast .alert`, `.ab-toast` |
| Hover, focus and button/link state | 110 ms of background and border, `--ease-standard` | `button, a`, `.ab-btn`, `.ab-need` |
| Voice bars | slow loop only under `no-preference`; it communicates real state, not decoration | keyframes `voice-flow` |
| DeepSeek peak flame | 2.6 s flicker of the flame's scale from its base, `--ease-standard`, only under `no-preference` and only while `Providers.peak?/1` is true; off-peak the moon is still. The switch itself is a cut: the icon changes at the hour | `.ab-peak.is-peak .hero-fire` |
| Throughput value that changed | 600 ms of color, `--agent` → `--ink`, `--ease-standard`; the `ValueChange` hook compares the previous value and only then applies `.is-changed`, so a broadcast with no change moves nothing, and nor does the runner's first answer after `?` | `.ab-flow__value.is-changed` |
| Current hour's sparkline bar that rose | grows from its old height (`scaleY`, origin at the base) in 180 ms on `m3.standard` (0.2, 0, 0, 1), Web Animations, only when the bar's hour is the same as before; a new hour, a bar that fell and the first bar of an hour (it had no rect) are cuts | `.ab-flow__spark rect.is-now` |
| Lane count that changed (Agora, Precisa de você, Fila) | the same 600 ms tint as throughput, from `--agent` back to the count's own ink: the number says it changed without moving | `.ab-sec__count.is-changed` |
| Messages or Attention badge that rose | one 200 ms bump to scale 1.2 at 35 %, `--ease-standard`; only a rise (`is-up`) bumps, a count the owner brought down by reading is a cut, and a badge that appears from 0 bumps because the summary, not the badge, carries the value | `.ab-hub-menu summary.is-up .ab-hub-menu__count` |

## What does not move

- Cards and rows that arrive from sync, stream or poll: the new node appears,
  without replaying an entry. The entry belongs to the surface, not to the data.
- Reconnection, periodic refresh and repository switch. A counter that changed
  tints in place (above); it never counts up or slides.
- Content text: it appears; it does not slide, blur or type (except when the
  product literally transcribes speech or writing).
- No blur-in, fade-up on everything, shimmer, drifting glow or floating card.
- No animation delays submit, click, navigation or reading.

## Reduced motion

Under `prefers-reduced-motion: reduce`, animations and transitions are turned off
in the global block. The state remains readable: the panel opens at once, the
notice appears, and the loading feedback stays textual and visual. Remove the
motion, never the feedback.

## How to validate

1. Run `make frontend` to generate the assets (the CSS has no separate step).
2. In the browser, open a panel and a notice; check the curves
   and durations in the DevTools Animations panel or in a trace.
3. Emulate `prefers-reduced-motion: reduce` and repeat: nothing animates and the
   states remain clear.
4. Repeat click, failed submit and reconnection: the animation does not queue,
   does not block and does not replay the list.
5. Record what you observed and what was not observed. A screenshot proves
   neither motion nor interaction.

## Maintenance

Changed a duration or curve? Update the token, the table above and the browser
check, in the same change. If the improvement is reusable, propose it in the kit
([evolution policy](agent/practices.md)); this board's rules and tokens stay
local.
