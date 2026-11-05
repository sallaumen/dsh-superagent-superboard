# Voice presence review

Baseline: `03542c0`, WebKit at `http://127.0.0.1:4002`, dark 1600×900. The baseline voice controls were inside Settings > Voice; the only activity indicator was the small `#voice-feedback` line in the header. See `before-settings.png`.

The after screenshots show the same board with the temporary voice surface. `after-listening.png` used a dummy `ELEVENLABS_API_KEY`, a mocked `MediaRecorder`/microphone and a routed local transcription response. `after-speaking.png` used a routed audio response and a mocked media element that emitted `playing` without sound. `after-speaking-mobile-light.png` is the same speaking state at 375×812 in the light theme. `after-error-mobile.png` used a routed HTTP 429 JSON response. No request reached ElevenLabs, no real task was created, and no message was sent.

| Check | Result |
|---|---|
| Dictate task from Settings | Opened New task first; recording button remained inside the form. |
| Listening | Surface showed the microphone state in the secondary theme color; button named “Stop & transcribe” kept its icon and accessible name. |
| Transcription | Stopping filled the editable task title and focused it; no form submission. |
| Speaking | Surface used the accent theme color only after the media element emitted `playing`; Stop voice paused playback. |
| Modal context | Opening a modal moved the active surface into it; its control stayed clickable. Closing a recording modal stopped the microphone. |
| Keyboard | On this macOS WebKit, Option+Tab reached Stop voice immediately after the header controls; `:focus-visible` matched. Plain Tab skipped all buttons in the browser's default keyboard-navigation setting. |
| Layout | No horizontal overflow at 375×812, 1366×768 or 3440×1440. |
| Motion | With `prefers-reduced-motion: reduce`, the bars had `animation-name: none`. |

A physical microphone and the real ElevenLabs service were not exercised. The waveform is a phase animation, not an amplitude meter; it does not claim to measure loudness.
