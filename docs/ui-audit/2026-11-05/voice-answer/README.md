# Natural board answer — visual check

The before state is PR #225's command panel on `main` at `46a3fe8`:
[1366 × 768](../voice-actions/after-1366.png) and
[3440 × 1440](../voice-actions/after-3440.png).

The after state is this branch's answer panel:
[1366 × 768](answer-1366.png) and [3440 × 1440](answer-3440.png).

WebKit loaded `sallaumen/o_colmex` with `?panel=voice`, submitted only the
read-only question “What is running?”, and displayed the explicit “AI answer”
label. The app used the local rehearsal fixture with a dummy provider key, so
no model request or microphone capture occurred. The latest completed sync
was two minutes old, and the answer visibly showed “update delayed” beside
its age. An earlier browser pass with a failed sync displayed “Sync failed ·
showing saved data”. There was no horizontal page overflow at either size,
and the browser console reported zero errors and zero warnings. The result
was text only; it did not play speech.

This check verifies the rendered states and labeling. The fixture cannot prove
that a remote model will always respect the bounded facts in its prompt.
