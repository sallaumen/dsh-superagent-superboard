# Read-only voice commands: browser evidence

Baseline: `3ec6c4d` (double-Space capture PR). After: PR #223. The same saved
repository, `sallaumen/o_colmex`, was viewed in headless WebKit at
`http://127.0.0.1:4002` before and `http://127.0.0.1:4007` after. No real
microphone, ElevenLabs request, task action, or GitHub write was used.

| Viewport | Before | After |
| --- | --- | --- |
| 1366×768 | [Before](voice-read-before-1366.png) | [Command action](voice-read-after-1366.png) |
| 3440×1440 | [Before](voice-read-before-3440.png) | [Command action](voice-read-after-3440.png) |

Additional states: [grounded result at 3440×1440](voice-read-result-3440.png)
and [grounded result at 375×812](voice-read-result-375.png).

The browser's media and transcription APIs were mocked before the keyboard
gesture. Two Space presses started one capture; two more ended it. The mock
recorded exactly one `getUserMedia` call, one track `stop`, and one simulated
transcription upload. The returned transcript was `show blocked tasks`.

The new submit action returned the saved blocked count, named the selected
repository, and explicitly said that the latest sync failed and saved data age
was unknown. Submitting `archive task 12` stayed in the voice panel as an
unknown read-only command with the edited draft preserved. Submitting
`abrir atividade` opened Activity; browser Back closed it directly to the
board, without reopening the voice draft. The action had an accessible name
and a visible 2px focus outline in WebKit. Console: zero errors; one warning
came from Phoenix's development live-reload channel.

The real device test with Wispr remains part of the final integration battery;
browser media mocks cannot establish operating-system microphone coexistence.
