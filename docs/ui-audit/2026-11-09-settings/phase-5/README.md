# Settings, phase 5: System

Baseline: phase 4 (`8d16b35`). Preview: isolated test node on port 4008
(`MIX_ENV=test MIX_TEST_PARTITION=ui_review`), a temporary fixture with a
repository and six activity events. A fake `git` on `PATH` (only inside this
preview, not committed) reports the served commit `a7adfab`, main `a9aef67`
and five commits between them, so the card shows the real "behind" layout and
a commit list. Headless Chromium, locale `pt-BR`.

The fixture and the fake git live in `tmp/`/`/tmp` and are not committed; the
real board and its service checkout are untouched.

| Before (#472: version + modal link) | After: version and browser |
|---|---|
| [before-desktop-dark.png](before-desktop-dark.png) | [desktop-system-dark.png](desktop-system-dark.png) |
| [before-desktop-light.png](before-desktop-light.png) | [desktop-system-light.png](desktop-system-light.png) |

| After: browser and activity | Phone dark | Phone light |
|---|---|---|
| [desktop-system-bottom-dark.png](desktop-system-bottom-dark.png) | [mobile-system-dark.png](mobile-system-dark.png) | [mobile-system-light.png](mobile-system-light.png) |
| [desktop-system-bottom-light.png](desktop-system-bottom-light.png) | | |

A mobile "before" capture is not available from the earlier phases.

Observed:

- The version card is one card: state (glyph + word), served/main shas, the five
  commits with hash/title/#PR, the plain interruption text and only the
  actions that apply (Check again, Restart only, Update and restart; Restart to
  apply when the checkout already downloaded the code). The old `.version-*`
  instrumentation styles are no longer fighting the card.
- "Neste navegador" has Tema (Sistema/Claro/Escuro, segmented with
  `aria-pressed`) and Idioma do board (English/Português, segmented); the note
  points to the voice language in Voice and summary.
- Activity is inline, no modal: repeated errors become one halt row with
  "Ver os erros" (the reasons are read on demand, from the last 200 events);
  consecutive reads without change become one row with "Mostrar"; a read with
  new commits is its own row; a per-item error keeps its reason. Every row has
  a glyph + word and an age, except when every timestamp is ahead of the board
  clock: then one stale note explains it and the times read `—`.
- The Activity modal and its temporary System link are gone. `panel=activity`
  is no longer a URL; the old activity tests were rewritten against the inline
  section.

The fixture's data is illustrative (the errors/reasons and commit titles), not
a replay of a real project.
