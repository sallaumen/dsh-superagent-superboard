# Voice commands: implementation plan

Status: proposed implementation sequence, 2026-11-05. The interaction decisions
under **Agreed behavior** come from the user's choices. The sequencing and time
limits below are implementation proposals to verify in a browser before release.

## Goal

The board listens only after two presses of the plain Space key in its active
browser tab. It gives short, grounded answers about the selected repositories
and can prepare coding requests for review. A transcript alone never sends a
message, creates a task, or changes a task's state.

## Current seams

- `assets/js/hooks/voice_recorder.js` owns `getUserMedia`, `MediaRecorder`,
  transcription upload, and track cleanup. It currently starts from clicks on
  form-specific microphone buttons.
- `assets/js/app.js` also starts browser `SpeechRecognition` after the
  `phx:dictate` event. Browser speech input has a second microphone owner.
- `lib/agent_board_web/live/board_components/create_task.ex` and
  `conversation.ex` render the recording buttons. `settings_menu.ex` links to
  dictation. Their existing text fields remain useful.
- `assets/js/voice_state.js`, `hooks/voice_presence.js`, and the
  `VoicePresence` component already display permission, listening,
  transcribing, speaking, completion, and error states. Reuse these states.
- `POST /api/voice/transcribe` already sends audio to ElevenLabs and returns
  text. `BoardLive` and `AgentBoard.Voice` already support spoken board status.
  The existing AI registry and budget remain the boundary for model calls.

## Agreed behavior

1. Only a valid double Space may **start** the board microphone. Clicking a
   microphone icon, opening a panel, reconnecting, or receiving a broadcast
   must never start it. Remove the current click-to-record and browser speech
   input entrypoints; keep text entry. A button may finish or cancel an active
   recording, but may not start one.
2. The shortcut is scoped to the visible, active board tab. It does not fire
   while typing in an input, textarea, select, or editable element, while using
   a button or menu, during composition, with modifiers, or from key repeat.
   A single Space scrolls after the short recognition window or before the
   next key; a double Space does not move the board. If a pointer action starts
   during that window, the click takes precedence and the pending scroll is
   discarded so its target cannot shift under the pointer. Check this in
   WebKit before settling on a key-event strategy.
3. One session owns at most one media stream. Stop its tracks before sending
   audio for transcription. Cancel and release them on Escape, tab hide,
   `pagehide`, panel or context exit, LiveView disconnect, recorder error,
   device end, and a short maximum duration. If a permission request resolves
   after cancellation, stop the newly returned tracks immediately. Do not
   retry capture or a paid transcription automatically.
4. Listening and speaking are mutually exclusive. The existing large voice
   surface must describe the **actual** phase; its visual bars are decorative
   unless connected to measured input levels. Respect reduced motion and keep
   a text status for assistive technology.
5. *(Superseded on 2026-11-07 by the owner's request for a hands-free
   conversation, see [voice-conversation.md](voice-conversation.md): the
   transcript is no longer shown for review; writes now wait for a spoken
   yes instead of a click.)* Transcription opens an editable command draft. The user decides whether to
   run a read-only command or proceed to a task or message form. Actions that
   write to GitHub or change task state require an explicit review of target
   and effect and a separate confirmation in the UI.

## Delivery order

| PR | Small, reviewable result | Primary files | Acceptance gate |
| --- | --- | --- | --- |
| 1. Single microphone owner | Double Space starts one capture session; second double Space finishes; Escape cancels. Remove every click path that starts input capture, including browser `SpeechRecognition`. Put the transcript in a reviewable command draft. | `assets/js/app.js`, `assets/js/hooks/voice_recorder.js` or a new single-purpose hook, `assets/js/voice_state.js`, `lib/agent_board_web/live/board_components/{create_task,conversation,settings_menu,voice_presence}.ex` | No `getUserMedia` before the gesture; one call after it; all exit paths stop tracks; text fields and single Space work normally. |
| 2. Read-only commands | Resolve simple commands deterministically: open a panel, select a repository, find a task or PR, explain current status. Show source and age when answering. Unknown or ambiguous requests stay as a draft. | A small web-layer command dispatcher and focused LiveView events/components | No fabricated values; no network write; no duplicate navigation or history entries; keyboard and reconnection tests. |
| 3. Natural-language answers | Use a registered, budgeted AI call only when deterministic matching is insufficient. Ground the prompt in the board's current snapshot; say when the snapshot is stale. Keep text feedback if TTS fails. | `AgentBoard.AI.Registry`, a focused voice command module, existing ElevenLabs output path | Every model call is recorded, paid failures are explicit, no automatic paid retry, and replies cite their data age in the UI. |
| 4. Coding requests | Convert a spoken request into an editable intake draft. Present repository, proposed scope, and exact downstream action before submission. | Existing intake and board UI components; existing domain APIs | Speaking alone never creates an issue, posts a comment, or starts coding. Submission tests cover wrong repository, stale state, and cancellation. |
| 5. Controlled mutations | Add selected task actions only after their read-only and draft paths are stable. Require a UI confirmation that names the target and effect. | Existing Board action events and confirmation UI | No action from transcript or spoken assent alone; audit trail and error state match actual backend result. |

PR 1 is the prerequisite for every later PR. PRs 2 and 3 can remain separate so
that navigation does not depend on a model or ElevenLabs availability. PRs 4
and 5 depend on the command draft and the read-only resolver.

## Verification for each implementation PR

- Update existing LiveView tests that currently expect click-to-record and the
  `dictate` event. Preserve unrelated `phx-click` and `phx-submit` names and
  payloads. Add meaningful tests at each new browser/server seam.
- Use the configured Playwright WebKit browser with a mocked media stream and
  mocked transcription response; do not open the real microphone or send real
  messages during automated review. Check keyboard focus, single versus double
  Space, editable targets, a second gesture, Escape, permission arriving after
  cancellation, tab hide, disconnect/reconnect, duplicate events, and console
  errors. Capture matching before/after screenshots for visual changes at
  1366×768 and 3440×1440, plus a narrow viewport and reduced motion.
- Run `scripts/ci-local.sh all` before each PR, including `mix gate`,
  `scripts/check_assets.sh`, and asset build as specified in `PIPELINES.md`.
  Record the local command and result in the PR while CI is blocked by billing.
- A human device check remains necessary: with the board idle, test Wispr in
  another app; use one board voice session; verify Wispr works again after the
  board session ends. Inspect the system microphone indicator and the selected
  device if it fails. Browser mocks cannot establish macOS device coexistence.

## Boundaries

The shortcut does not become a system-wide wake word. The board does not keep a
background listener. Audio is sent to the existing transcription endpoint only
after the user records; proposed command history should store intent, target,
confirmation, and result rather than raw audio. Any retention or provider
privacy claim must be verified against the actual service contract before it
appears in the UI.
