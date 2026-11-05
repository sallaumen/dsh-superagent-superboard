# Integrated voice UX battery — 2026-11-05

This run used PR #222 on top of #224, #223, #225, #226 and #221. The server ran in `MIX_ENV=test` at `localhost:4008`, with `DEEPSEEK_API_KEY=fixture`, `ELEVENLABS_API_KEY=fixture`, AI rehearsal enabled before application start, WebKit `getUserMedia`/`MediaRecorder` mocks, and a mocked transcription endpoint. `fixture/voice-final` had one queued task (`#42`); `fixture/voice-stale` had a sync failure event. Both repositories, the task, event and two rehearsal AI rows were removed after the run. The test database returned to zero repositories, tasks, comments and AI calls.

## Screen evidence

| State | Screenshot |
| --- | --- |
| Light board, 1366×768 | [light](voice-final-light-1366.png) |
| Dark board, 1366×768 / 3440×1440 | [1366](voice-final-dark-1366.png) · [3440](voice-final-dark-3440.png) |
| Listening, then editable transcript | [listening](voice-final-listening-1366.png) · [draft](voice-final-draft-1366.png) |
| Read question answered by rehearsal | [AI answer](voice-final-ai-1366.png) |
| Coding request prepared without Split | [1366](voice-final-intake-1366.png) · [3440](voice-final-intake-3440.png) · [375](voice-final-intake-375.png) |
| Stop preview without confirmation | [1366](voice-final-action-1366.png) · [375](voice-final-action-375.png) |
| Failed sync and disconnected LiveView | [saved data](voice-final-stale-1366.png) · [reconnecting](voice-final-reconnecting-1366.png) |

## Browser checks

- The theme controls switched `data-theme` from dark to light and back. The board background computed as `oklch(0.96 0.009 85)` in light and `oklch(0.28 0.021 250)` in dark; the chosen button reported `aria-pressed=true`.
- One Space requested the microphone 0 times. Two Spaces requested it once and started one recorder. The second pair stopped one track and made one mocked transcription upload. The editable draft was `show blocked tasks`; focus moved to the voice dialog heading. Two Spaces inside the textarea inserted text and made no new microphone request.
- Escape during listening stopped its track without uploading. When a pending permission resolved after Escape, that late track was stopped without starting a recorder or uploading.
- `show blocked tasks` returned the saved exact total of 0 and said the data age was unknown because there was no sync. `What is the board doing?` produced one labeled `AI answer` from the rehearsal fixture, with `Sync time unknown`, and did not request speech audio.
- Editing the draft and immediately choosing **Prepare coding request** opened the intake with the exact current text, selected repository, a review note and an explicit description of Split's effect. No Split or issue creation was invoked. Browser Back returned to the voice dialog with the draft intact and focus on its heading.
- `stop task #42` displayed the saved title, repository and GitHub-closing effect. No Confirm button was activated. `archive task #999` returned a missing-record error and no action review.
- `sync_error` showed “showing saved data” and “Saved data age: unknown” in the header and the AI result. A simulated LiveSocket disconnect changed the visible indicator to reconnecting; reconnect restored live. The focused draft stayed `status`, its focus stayed in the textarea, and the one task card remained one card.
- The 375 px intake and Stop preview had no horizontal document overflow. The browser session had **0 console errors and 0 warnings**.

The task remained `{queued, stopped: false, archived: false}` with no comments or events in its repository. The two AI rows had `answer_board_question`, `rehearsal`, `ok`. No real microphone, model, ElevenLabs transcription or GitHub write was used.

## Finding during integration

The Ask confirmation added by #226 could not be reached by a person dictating from an open conversation: the recorder rejected double Space whenever any board dialog was open. A focused follow-up PR will allow the shortcut from a neutral conversation heading while keeping it blocked in text fields and other dialogs. This battery is the pre-fix record; repeat the conversation voice path and the final gate on main after that fix.
