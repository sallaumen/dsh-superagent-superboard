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
