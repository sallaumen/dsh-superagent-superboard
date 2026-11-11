# Provider credits on the board

The owner asked to follow ElevenLabs' cost and limit in the settings, to have the voice switch to the computer when the credits run out, and to see in the alerts when any provider runs out.

What the board knew before: only the characters it spent itself per UTC day, against its own cap of 20,000 a day (`ELEVENLABS_DAILY_CHAR_CAP`). The account, read on 2026-11-11, is on the free tier with 10,000 characters a period (4,177 used, renewal 2026-12-06 01:42 UTC): the board's daily cap was above the whole plan, so it never switched in time. A refused speech for spent credits (`quota_exceeded`, which ElevenLabs answers as 400 or 401) read as "the key was rejected", and the browser went silent.

Now:

- **Settings → Voice** prints the plan under the title: `ElevenLabs · plano: 4.177 de 10.000 caracteres neste período, renova 5 dez` (`voice-plan-pt-light-1920.png`). The account is read every 15 minutes with `GET /v1/user/subscription`, which spends no characters. ElevenLabs bills credits of the plan, not a price per call, so the board shows characters, not dollars.
- **Spent credits** are their own reason. The paid voice is off for an hour after a refusal, or until the plan renews when it has no characters left; meanwhile every utterance goes to the computer voice. A paid audio that fails in the browser is spoken there with the same text.
- **The Attention bell** lists, first, the providers that cannot serve: ElevenLabs spent, the board's AI budget spent, a provider whose newest board call of the last day was refused for limit or balance. Each opens its settings section (`bell-provider-pt-light-1920.png`).

Captured on an isolated server with a copy of the data and no keys: the plan numbers are the ones read from the account on 2026-11-11, put in the board's memory by the start script; the bell item is the AI budget, spent with `AI_DAILY_TOKENS=0`. Clicking it opened Settings → Execution. Not observed: a real `quota_exceeded` and the browser falling back to the computer voice in a real browser.
