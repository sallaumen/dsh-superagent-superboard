# The last interface text outside Gettext, 2026-11-10

Workflow: `house-patterns` (Elixir Agent Kit 0.8.0), medium.

## Pattern card

- Rule: interface copy goes through Gettext with an English msgid; Portuguese
  lives in the catalog (`docs/maintainer-contract.md`, "Interface language").
- Search: string literals in `lib/` and `assets/js` that read as Portuguese and
  are not inside a Gettext call (443 lines in 34 files on `main` at b903262).
- Behavior kept: with the Portuguese cookie every screen reads as before.

## Deviation table

| Site | Lines | Disposition |
|---|---|---|
| "What can I ask?": group titles, what each command does, how it runs (`Voice.Commands`) | 35 | **conformed**: English msgids marked in the data, translated where shown. What to say stays in the voice's language |
| Flashes and composer errors in `BoardLive` | 5 | **conformed** |
| Voice model notes in the settings picker (`ElevenLabs`) | 3 | **conformed** |
| `Actions`: confirmation sentences and results | 71 | cleared: already two languages by the `lang` argument (#529, #533); the `does` catalog is not shown anywhere |
| `assets/js`: 43 strings in five hooks, `i18n.js` | 90 | cleared: every call site goes through `localize`; the map is keyed by Portuguese |
| `Metrics` tile labels | 2 | cleared: the screen labels tiles by key through Gettext |
| `Voice.Phrases`, `Phrases.DailySummary`, `VoiceAnswer`, recognition words in `Conversation.Agent` and `VoiceCommands` | ~135 | kept: spoken or heard, they follow the voice language, its own setting |
| `IssueBody`, `Unblock.blocker_title`, `AI.Registry`, `Rehearsal`, `Workpad` headings | ~28 | kept: text written to GitHub, prompts, fixtures, the agent's own headings |
| `Freshness` | 31 | kept: not rendered |
| **Stored text**: voice activity details (`VoiceConversation`, `VoiceController`, `Voice.Activity`, `Conversation.Agent`, `ElevenLabs.Usage`), event subjects (`AutoRetry`, `AgentControl`, `AgentFailure.describe`), superagent and runner errors (`BotAccess`, `DshManager`, `AgentControl`, `Runners`) | ~45 | **handed off**: written once, in Portuguese, and shown later to any viewer. Needs a decision (below) |

## The decision left

Stored text is written by background processes that have no viewer and no
locale. To read in the viewer's language it must be stored as a code with its
values and worded where it is shown, as the task Activity already does for
retries (#537). Until then it stays Portuguese in both languages. The
alternative, English from now on with old rows left as they are, makes the
Logs panel English for a Portuguese viewer.

## Checked

- [01](01-voice-commands-dark-en.png), [02](02-voice-commands-dark-pt.png): the list in both languages on a copy of the real data.
- `voice_command_list_test.exs`: both languages, and every title and description has its Portuguese.
