# Two lanes in a 1280 px window

Finding 17 of the [experience audit](../board-experience-audit/README.md): a 1280 px window (1920 at 150 %) gave one lane column 976 px wide. The owner chose two columns on 2026-11-10.

The container query measures `main`'s content box, so its 1000 px needed a 1304 px window. The cut is now 960 px, a 1264 px window. Below it nothing changes; the three-lane layout still starts at 1300 px of content.

Measured on an isolated server, with a copy of the development data and ten fixture tasks (numbers 9001 to 9010) so the lanes have content, in WebKit:

| Window | Lanes | Column widths |
|---|---|---|
| 375 | 1 | 343 |
| 1263 | 1 | 959 |
| 1264 | 2 | 460, 460 |
| 1280 | 2 | 468, 468 |
| 1440 | 2 | 548, 548 |
| 1920 | 3 | 456, 456, 593 |
| 3440 | 3 | 401, 401, 521 |

No horizontal page overflow at any width, on the three projects. At 1280 px the lanes go from 915 px tall to 762 px, and Queue starts beside Now instead of below Needs you.

`before-1280.png` is the same page with the old one-column layout applied by a style override. `after-1280.png` is this change. Emulated viewport; not checked on the owner's monitor at 150 %.

## A long queue

The first version left a hole: Queue spans both rows, so a tall queue split its extra height between them and pushed Needs you down. With the queue expanded (1669 px) at 1280 px, the space between Now and Needs you was 494 px. The rows are now `auto 1fr`, so the extra height goes under Needs you: 40 px, the normal gap (`after-long-queue-1280.png`, 45 fixture tasks). From 1300 px of content the three lanes use one row, with no empty strip below them at 1920 and 3440 px.
