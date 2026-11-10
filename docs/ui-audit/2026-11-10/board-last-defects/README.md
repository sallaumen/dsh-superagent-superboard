# The last small defects of the audit, 2026-11-10

Workflows: `layout-density` (the Cycle tile, the rail) and `house-patterns`
(the flashes), Elixir Agent Kit 0.8.0, small.

| Audit finding | Before | Now |
|---|---|---|
| 16: the Cycle tile cut its values ("4 h 15…") | a 173 px table (1920, and 2560 with the inspector) cut "23 h 59 min" in all four value cells | a duration wraps between its parts ("23 h" / "59 min"); no cell is cut from 1280 to 3440, with and without the inspector, in both languages |
| 21: opening the inspector above 1880 px of board widened the rail from 224 to 240 px | the rail moved under the reader | the rail stays 224 px; only the panel grows to 520 px |
| Interface text outside Gettext | six flashes: four English (split, task created), two Portuguese (voice picker) | through Gettext, both languages |

The ready-to-send examples of "What can I ask?" were run through the matcher
used without a model: in both languages only "Status" resolves there, and the
rest are questions for the model. English is no worse than Portuguese.

## Checked

Isolated server on a copy of the real data, measured in WebKit with the
longest duration the tile shows ("23 h 59 min") written into each cell:

- [01](01-cycle-1920-dark-en-tile.png): the tile at 1920.
- [02](02-cycle-2560-inspector-dark-en-tile.png): the tile at 2560 with the inspector open.
- Rail width 224 px at 1280, 1440, 1920, 2560 and 3440, with and without the inspector.

## Left to the owner

- 17: a 1280 px window gives one lane column.
- 18: a merged task's inspector still offers Ask, Stop and Archive.
- 20: "Agent offline" is both the label and the title of its card.
