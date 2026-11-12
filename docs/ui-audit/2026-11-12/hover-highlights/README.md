# Hover: what is under the pointer, and where else it is

Isolated server: the copy of the dev database (`agent_board_motion`) on port
4613 with a fresh sync event (so the board is live, not frozen) and a runner
`state_db` holding #229 as running. Headless WebKit at 1440 × 900, the mouse
moved with Playwright.

Before this change, hovering a card changed only its border to `--line-strong`
(or `--agent` on Agora) or its background to `--surface`, with no transition,
and nothing told you the same task also showed elsewhere.

Each sheet stacks, top to bottom: rest, mouse at the left of #229 (Agora),
mouse at the right of #229 (the light followed), mouse on the first card of
Precisa de você.

| Capture | What it shows |
|---|---|
| `light-sheet.png` | Agora's card takes a green edge and a soft green light under the pointer, which moves with it; the Precisa de você card takes a blue edge and a blue light. With the mouse on that need (#227), its row in Fila gets the fine related edge |
| `dark-sheet.png` | the same in the dark theme: the edge carries the colour, the light stays quiet |

Also checked in the page:

- related marks: hovering #229 in Agora marked `objective-tree-node-57022` and
  `slow-57022` (its "taking long" notice); hovering the queue row of #227
  marked `objective-tree-node-57020` and `unanswered-57020`;
- `--mx` follows the pointer (80 px after a move) under `no-preference`, and
  the light's opacity transition is 120 ms in;
- under `prefers-reduced-motion: reduce`, `--mx` stays empty (centred light)
  and the transition is `0s`. The global reduced-motion block does not reach
  `::after`, so the stylesheet cuts it explicitly; found while checking.

Not observed: keyboard focus on a card (same rule as hover, `:focus-visible`),
the objective tree's own hover (not on screen at this height), touch (no light
by design), phone width.
