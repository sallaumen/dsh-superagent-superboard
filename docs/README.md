# Super Board documentation

[Project overview](../README.md) · [Primeiros passos em português](primeiros-passos.md)

## Use the board

| What are you trying to do? | Start here |
| --- | --- |
| See issues and PRs from your first repository | [Install the board and connect GitHub](getting-started.md#track-a-github-repository) |
| Let DeepSeek implement a GitHub issue | [Connect the Super Agent](getting-started.md#connect-the-super-agent) · [See how a mention becomes a PR](agent/how-it-works.md) |
| Break down a request or choose between DeepSeek, Claude Code and Codex | [Walk through your first request](first-request.md) |
| Ask a question out loud and hear the answer | [Try a voice turn](first-request.md#talk-to-the-board) · [Voice settings, commands and costs](voice-conversation.md) |

## Operate and integrate

- **Board:** [Run it as a service, configure credentials or troubleshoot sync](operations.md).
- **Agents:** [Install on another machine, configure a second profile or change merge policy](agent/setup.md). For a guided introduction to the Harness, follow the [learning path](agent/learning-path.md).
- **API:** [JSON routes, request bodies, responses and side effects](api.md).

## Develop and maintain

- [Contribution workflow](../CONTRIBUTING.md) · [Required checks](../PIPELINES.md) · [Working in parallel branches](agent/collaboration.md)
- [Architecture and data owners](architecture/README.md) · [Maintainer contract](maintainer-contract.md) · [Interface motion](ui-motion.md)
- [Architecture decisions](decisions/README.md) · [Shared engineering practices](agent/practices.md)
- [Agent communication](agent/prompts/communication.md), [scope](agent/prompts/scope.md) and [delivery](agent/prompts/delivery.md) prompts
- [Evaluate the board’s AI](board-ai-evaluation.md) · [Evaluation results](evaluations/README.md) · [UI audits](ui-audit/README.md)

<details>
<summary>Research and earlier proposals</summary>

These are design records. Use the guides above for current behavior.

- Research: [Alfred and executor routing](research/alfred.md), [Symphony](research/symphony.md), [Super Agent provisioning](research/superagents.md), [bug audit](research/bug-audit-2026-11-09.md).
- Earlier proposals: [board AI layer](ai-layer.md), [voice commands](voice-command-plan.md) and [voice output](voice-output-plan.md).

</details>
