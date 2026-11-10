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
| Opening the settings menu | 160 ms, opacity + 4 px up, `--ease-enter` | `.board-settings-body` |
| Temporary notice (toast) | 200 ms, opacity + 4 px, `--ease-enter` | `.toast .alert` |
| Hover, focus and button/link state | 110 ms of background and border, `--ease-standard` | `button, a` |
| Settings and section chevron | 160 ms of rotation; the state remains readable without motion | `.settings-chevron`, `.settings-fold-chevron` |
| Attention dot and voice bars | slow loop only under `no-preference`; it communicates real state, not decoration | keyframes `attention-breathe` and `voice-flow` |
| Throughput value that changed | 600 ms of color, `--agent` → `--ink`, `--ease-standard`; the `Throughput` hook compares the previous value and only then applies `.is-changed`, so a broadcast with no change moves nothing, and nor does the runner's first answer after `?`; the new sparkline bar just appears | `.ab-flow__value.is-changed` |

## What does not move

- Cards and rows that arrive from sync, stream or poll: the new node appears,
  without replaying an entry. The entry belongs to the surface, not to the data.
- Reconnection, periodic refresh, repository switch and counter updates.
- Content text: it appears; it does not slide, blur or type (except when the
  product literally transcribes speech or writing).
- No blur-in, fade-up on everything, shimmer, drifting glow or floating card.
- No animation delays submit, click, navigation or reading.

## Reduced motion

Under `prefers-reduced-motion: reduce`, animations and transitions are turned off
in the global block. The state remains readable: panel and menu open at once, the
chevron turns at once, the notice appears, and the loading feedback stays textual
and visual. Remove the motion, never the feedback.

## How to validate

1. Run `make frontend` to generate the assets (the CSS has no separate step).
2. In the browser, open a panel, the settings menu and a notice; check the curves
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
