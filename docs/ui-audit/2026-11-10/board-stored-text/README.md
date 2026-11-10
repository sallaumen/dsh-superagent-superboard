# Stored text in English from now on, 2026-11-10

Workflow: `house-patterns` (Elixir Agent Kit 0.8.0), medium. Owner's decision
of 2026-11-10, after the inventory in `../board-languages-last/README.md`.

## Pattern card

- Rule: text the board stores or logs once and shows later to any viewer is
  written in English (`docs/maintainer-contract.md`, "Interface language").
- Search: `Activity.record(` details, `Board.log_event` subjects, stored
  errors of superagents and runner executions.
- Kept: what callers observe apart from the language. Statuses, kinds,
  payloads and the answers given to the person who acted are unchanged.

## What changed

| Site | Messages |
|---|---|
| Voice activity details and reasons (`VoiceConversation`, `VoiceController`, `Voice.Activity`, `Conversation.Agent`, `ElevenLabs.Retry`, `ElevenLabs.Usage`, two in `BoardLive`) | 44 |
| Retry event subjects (`AutoRetry`, `AgentControl`); `AgentFailure.describe/1` is now the English of `headline/1` instead of a second list of eleven Portuguese sentences | 11 |
| Stored errors: `BotAccess` (3), `DshManager` (2), `Runners` (3), `AgentControl` (2) | 10 |
| One flash that was Portuguese in both languages ("Nothing was erased: confirm to forget.") moved behind Gettext | 1 |

## What a Portuguese viewer sees

The Logs panel's voice activity, the subject line of a retry in Settings →
Activity, and a superagent's or a runner's stored error read in English from
now on. Rows written before stay in Portuguese. The task's own Activity tab
still reads in the viewer's language: it words retries from the event's kind
and values (#537).

## Checked

- The whole suite, with the eight test files that pinned the Portuguese text updated.
- No capture: the text only appears when the event happens, and no screen changed its layout.

## Left as they are

- `Runners.fallback/1` still recognizes "teto de orçamento" in an old row's error.
- The settings screen still recognizes "não aponta" beside "does not point".
- Routing reasons are stored in the language they were shown in (an earlier owner's decision).
