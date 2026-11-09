# Plan: the agent's voice speaking to the owner

> **Historical record:** a plan from 6 November 2026, before the implementation.
> The items marked "(chosen)" have already been delivered; the current rules are
> in [maintainer-contract.md](maintainer-contract.md#the-voice) and the current
> usage in [voice-conversation.md](voice-conversation.md). The postponed items
> (B6, B7, U6) remain postponed.

Kit workflow: `notifications` (what is spoken, when, how many times and why it
repeats). Date: 2026-11-06.

## What exists today

- `AgentBoard.Announcer` decides what to speak when the board changes;
  `BoardLive.speak/2` pushes `voice_play` and the `VoicePlayer` hook plays the mp3
  from `/api/voice/speech` (ElevenLabs).
- Without an ElevenLabs key, only the summary of the "falar" (speak) button uses
  the browser voice (`phx:speak`, `utterance.lang = navigator.language`).

## Problems observed in the code

| # | Problem | Where |
|---|---|---|
| 1 | Every spoken sentence is English ("Task 'X' is now running.", "Good morning", "The sync failed") while titles and voice are Portuguese: the mix comes from here. | `Voice`, `Announcer`, `BoardLive` |
| 2 | The `summarize_board` prompt does not state the language; the model answers in whatever language it wants. | `AI.Registry` |
| 3 | TTS does not force a language: Flash v2.5 accepts `language_code` and normalizes numbers and acronyms in the right language. | `ElevenLabs.speech/2` |
| 4 | A task that moves to `question` (the agent waiting for your answer) is not announced: `question` is not in the live lanes. | `Announcer` |
| 5 | Two changes in the same update become two `voice_play` events; the second cancels the first, so the first sentence is never heard. | `BoardLive.announce/3` + `VoicePlayer.play` |
| 6 | The greeting uses the UTC hour: at 22h in São Paulo (01h UTC) the agent says "Good morning". | `Voice.greeting/1` |
| 7 | Volume does not exist; the summary does not count pending questions. | `VoicePanel`, `Voice.summary/2` |

## Options

Backend

- **B1 Language of the voice** (chosen): key `voice_language` (`pt-BR` default,
  `en-US`); every spoken sentence comes from `AgentBoard.Voice.Phrases`; the
  summary prompt receives the language; TTS sends `language_code` on Flash.
- **B2 Attention calls** (chosen): a task entering question, block or review
  becomes a call, with 10 sentences per type in rotation (never the same twice in
  a row) and priority over the other news.
- **B3 One utterance per update** (chosen): the sentences of the same update
  become one, so none is cut off.
- **B4 More natural speech** (chosen): states with a spoken name ("em andamento"
  [in progress], "na fila" [in the queue]), a short title cut at a word, a
  greeting by the browser's local hour, the summary counts questions.
- **B5 Volume** (chosen): key `voice_volume` 0–100, validated, also in
  `PUT /api/voice/settings`.
- B6 Reminder: repeat the call if the task is still waiting for N minutes.
  Postponed: it needs a clock per task and a limit so it does not become
  insistence.
- B7 Quiet hours. Postponed.

Interface

- **U1 Volume** (chosen): slider with a percentage, applied immediately to the
  audio that is playing.
- **U2 Language** (chosen): picker at the top of the Voice section; when it is
  changed, the agent confirms in the new language.
- **U3 Two toggles** (chosen): "Chamar quando precisar de mim" and "Narrar o
  resto do quadro", separate, for whoever wants only the calls.
- **U4 Panel in Portuguese** (chosen): the section is already called "Voz"; the
  content was in English.
- **U5 Browser voice as a fallback** (chosen): without an ElevenLabs key, the
  calls use the browser voice in the chosen language.
- U6 A short sound before the call. Postponed.

## Next: your speech to the agent

The reverse path (dictation → command) is left for the next round. The natural
first step is to send the chosen language as a hint to Scribe
(`/api/voice/transcribe?language=pt`), which already accepts the parameter.
