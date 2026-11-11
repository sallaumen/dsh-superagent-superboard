# Settings: which AI does what, and a setup check — 2026-11-11

The owner asked for Settings to say which AI serves the superagents, the
board's own refinements and the voice; to group them in a few classes; to fit
Claude Code and Codex in with when and why to use each; and to offer a button
that validates the setup, as onboarding.

Captured on an isolated preview (a copy of the dev database, rehearsal AI, no
keys in the environment, runner disconnected; the superagents' own `/state`
answered read-only), WebKit, 1440 × 1000 and 390 × 844.

## Before

`before-execution-1440.jpg`: the AI was spread over Projects ("its DeepSeek
agent", no model), Execution (Claude Code, Codex, DeepSeek costs, and a fixed
sentence "The board uses deepseek-flash" whatever provider answered) and Voice
(ElevenLabs). Nothing said which AI does what, nothing proved a key worked
("connection not verified" only meant a variable was set), and no page said
how to set up Claude Code or Codex.

## After: Settings → AI and setup, the first section

| Class | Rows | When and why |
|---|---|---|
| Who does the work | GitHub, Projects, DeepSeek agents (model read from each profile), Claude Code, Codex | DeepSeek for everyday tasks (one agent per project, all day, the agent's DeepSeek account); Claude Code for large or delicate tasks (Max subscription, usage limit); Codex near Claude's limit or for a second opinion (ChatGPT weekly quota) |
| The board's own AI | the provider that answers, its model and the fallbacks | refines and splits requests, answers, unblocks, voice turns; pays per use with the API key, daily token ceiling |
| Voice | ElevenLabs or the browser | ElevenLabs sounds better and spends the plan's credits; the browser is free |

- Without a click, rows read configuration only: a key that is set is "Set, not checked" (`pt-1440-unchecked.jpg`).
- "Check the setup" proves each part with free reads (GitHub `/user`, the provider's `/models`, each agent's `/state`, `claude auth status`, `codex login status`, ElevenLabs' subscription), then shows a summary and the next step with its fix: a link to the provider's key page, a section of Settings, or the Terminal command (`pt-1440-checked.jpg`, `pt-1440-bottom.jpg`, `en-1440-bottom.jpg`, `pt-390-checked.jpg`). In this preview GitHub has no token, so it is the next step.
- No element runs past the pane and no horizontal scroll at 390, 1440 and 2560, in both languages.
