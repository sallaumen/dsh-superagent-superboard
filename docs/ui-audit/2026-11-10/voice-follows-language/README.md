# The voice speaks the interface language of each browser, 2026-11-10

Workflow: `data-contracts` (Elixir Agent Kit 0.8.0), large. Owner's decision
of 2026-11-10.

## Before

Two settings that nothing tied together: the interface language, per browser
(a cookie, English by default), and `voice_language`, one value for the whole
board (Portuguese by default). A fresh board showed English and spoke
Portuguese. Three stages followed neither.

## Ownership now

| What | Owner | Read by |
|---|---|---|
| the language spoken in a tab | the tab's interface language (`Locale.language/0`), put in `@voice.language` by `BoardLive` | phrases, the Announcer, the voice agent's `language`, the browser voice, the transcription hint, the speech URL |
| the language of one audio request | the `language` of the request (`/api/voice/speech`, `/stream`) | `VoiceController`; without one, no hint is sent |
| the saved `voice_language` row | nobody | ignored, not deleted |

## Gaps closed

| Stage | Before | Now |
|---|---|---|
| Replies given without a model (`VoiceCommands`) | English, always | Gettext under the turn's language (21 sentences, both languages) |
| The inspector's answer to a question (`:answer_question`) | "the question's language"; its failure text English | the tab's language, passed as `language`; the failure text through Gettext |
| "What can I ask?" | Portuguese only | 24 examples in each language |
| Voice agent and explain prompts | named only pt-BR, Portuguese examples | name both, an English example of an age |
| Issue title written by the voice agent | "the owner's language" | the language named by `language` |

## Removed

- The voice-language picker in Settings, its event, the `language` setting of
  `change_setting`, `Voice.language/0`, `Voice.put_language/1`,
  `Phrases.language_switched/1`.
- **Public API**: `language` left `PUT /api/voice/settings` and the status
  response. A client that still sends it is ignored. `GET/POST
  /api/voice/speech` and `/stream` take an optional `language`.

## Checked

Isolated server on a copy of the real data, which carries the owner's saved
`voice_language = pt-BR`:

- [01-en-voice-panel](01-en-voice-panel.png): a browser with no language cookie. The panel is English, "Status" answers "Good afternoon. On the board: 50 recent merges.", the examples read "How is the board?".
- [02-pt-voice-panel](02-pt-voice-panel.png): the same after choosing Portuguese: "Boa tarde. No quadro: 50 entregas recentes.", "Como está o quadro?".
- [01-en-voice-settings](01-en-voice-settings.png), [02-pt-voice-settings](02-pt-voice-settings.png): the picker is gone; a line says where the language comes from.

## Not checked

- No ElevenLabs key in the rig: the paid voice and the transcription were not heard. The request's `language_code` is asserted in `voice_controller_test.exs`.
- Whether the model writes titles and answers in the language it is told: only a live call shows it.
- Whether the saved ElevenLabs voice sounds right in both languages: it is one voice for both.
- The English examples marked ready-to-send were not tried against the no-model matcher one by one.
