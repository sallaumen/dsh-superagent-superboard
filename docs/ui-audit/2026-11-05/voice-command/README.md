# Double Space voice capture: browser evidence

Baseline: `9f9e8f4` (`main`). Local app: `http://127.0.0.1:4002/`.
Browser: configured Playwright WebKit, with `getUserMedia`, `MediaRecorder`,
and `/api/voice/transcribe` mocked for the recorded checks. No real audio was
recorded and no GitHub write was used. A development live-reload once removed
an in-page mock before a keyboard check; the browser reported microphone
unavailable, and that isolated tab was closed. The later checks installed
the mock before page load so it survived reloads.

| View | Before | After |
| --- | --- | --- |
| Board and listening, 1366×768 | [board](before-1366.png) | [listening](after-listening-1366.png) |
| New task, 1366×768 | [click-to-record form](before-create-1366.png) | [text-only form](after-create-1366.png) |
| Board and command draft, 3440×1440 | [board](before-3440.png) | [editable draft](after-draft-3440.png) |
| Command draft, 1366×768 | [board](before-1366.png) | [editable draft](after-draft-1366.png) |
| Command draft, 375×812 | — | [narrow viewport](after-draft-375.png) |

Observed with mocked media:

- Idle and one Space: zero microphone requests. Two Spaces: one request and a
  visible listening state. A second pair ended the recording, stopped its
  track, uploaded once, and opened the editable transcript in an in-page
  dialog. The sample transcript was a fixture (`show blocked tasks`); no
  command was executed.
- Escape while listening stopped the track without uploading. When permission
  resolved **after** Escape, the returned track was stopped immediately, also
  without uploading. A second check simulated losing window focus while
  permission was pending: when permission resolved, the track was stopped,
  the recorder never started, and no upload occurred.
- A single Space followed by another key replayed the document scroll once
  and made no microphone request. A single Space followed by a simulated
  LiveView context update also scrolled once. A valid double Space did not
  scroll. Space followed immediately by a click opened New task with no
  intervening scroll, so the click target did not shift.
- Two Spaces inside the New task title field inserted two spaces and made no
  microphone request. Browser Back and the dialog's Close button returned to
  the board URL. The 375px dialog had no horizontal page overflow.
- Browser console: zero errors. One dev live-reload warning reported a TLS
  connection on a clear channel; it was unrelated to the voice flow.

The actual macOS/Wispr microphone coexistence test remains pending and must be
performed on a real device before calling that integration verified. The
browser checks prove only the board's own mocked stream lifecycle.
