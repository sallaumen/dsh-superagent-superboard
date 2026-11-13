# Your first request

[Set up the board](getting-started.md) · [Português (Brasil)](primeiros-passos.md#do-pedido-às-issues)

## Review the issues

In **New request**, describe an observable result: “Customers can export the catalog as CSV.” Keep it as one issue for a small change. For a larger request, choose **Split automatically**. The board’s AI proposes titles, acceptance criteria and dependencies; you can edit them or leave tasks out before confirming. Splitting does not publish anything.

For example, **define the CSV columns** before **implementing the export**. Another task, **add a download icon**, can proceed independently. Once published, the issues stay grouped under one objective.

## Choose an executor

The AI that plans the work and the agent that writes code are separate choices. Configure the board’s provider in [local settings](operations.md#local-secrets). Choose an executor when you submit the request:

| Executor | How work starts |
| --- | --- |
| **DeepSeek Super Agent** | Its bot picks up addressed issues in repositories the profile watches. Dependent work waits until its prerequisites are released. |
| **Claude Code** | Choose Claude Code for the task, then open the task and confirm a local run with the signed-in `claude` CLI. |
| **Codex** | Choose Codex for the task, then confirm a local run with the signed-in `codex` CLI. This is the OpenAI/GPT coding path. |

You might send the CSV implementation to Claude Code and a separate request for the icon to Codex. **The board suggests; you decide.** Selecting an executor does not spread one request across several models automatically.

For DeepSeek capacity, **Parallelism** reads occupied slots against the profile’s worker limit: `2 of 4` means two busy workers. The waiting count is separate; `?` means the agent did not report a value. Claude Code and Codex runs do not consume those DeepSeek slots.

## Talk to the board

1. Open **Chat** (or press **Space** twice from the board) and select a **SuperBoard Skill** to try a status question by text.
2. For a spoken conversation, set `ELEVENLABS_API_KEY` in `.env.local`, restart the board and open **Settings → Voice and summary**. Select the board microphone for input, choose a voice and allow microphone access in your browser.
3. Ask what needs attention. **ElevenLabs Scribe** transcribes the question. With spoken replies enabled, choose a short or full answer; the text stays in Chat. Audio uses ElevenLabs credits. You can keep typing without a voice key.

[Voice controls, costs and troubleshooting](voice-conversation.md) · [Executor configuration](operations.md#local-secrets) · [How the agent works](agent/how-it-works.md)
