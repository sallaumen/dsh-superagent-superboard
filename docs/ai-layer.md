# The board's AI layer — a historical proposal

> **Historical record:** a proposal from 5 November 2026, before the AI layer was
> implemented. The text below preserves the diagnosis, the projections and the
> phases of that proposal; it does not describe the current state nor a list of
> tasks still pending. The references to `o_colmex` are the survey from that time,
> not an inventory verified by this repository. To work on the implementation,
> see the [AI rules](maintainer-contract.md#ai-calls) and the entry points
> [AgentBoard.AI](../lib/agent_board/ai.ex) and
> [AgentBoard.Intake](../lib/agent_board/intake.ex).

The board today **mirrors** the agent's work: it syncs GitHub, shows the board,
speaks the summary. It does not **call** any model. The `ask` is a GitHub
comment; the `Voice` is a template. This document maps what is missing for the
board to have its own AI layer — short, cheap and transparent — and what of it
can be borrowed from `o_colmex`, which has already solved this problem.

## 1. What `o_colmex` already has

| Contract | What it does | File |
|---|---|---|
| `Engine` (behaviour) | the port to a model: `run/1` and `status/0`; one adapter per engine, Mox in the tests | `lib/colmex/brain/engine.ex` |
| `Request` / `Result` | input (model, system, prompt, caps, schema, tier, route) and output (text, json, tokens, cost in micros, `parse_state`) | `brain/request.ex`, `brain/result.ex` |
| `Registry` | **literal list of the allowed calls**; the prompt is code, a worker does not invent a prompt | `brain/registry.ex` |
| `Router` | picks the engine by `tier`, remaining quota and `recommended`; it only switches on a definitive response | `brain/engines/router.ex` |
| `Providers` | catalog: engine, pool, model per tier, prices, capabilities | `brain/providers.ex` |
| `Cut` | the paid response that came back incomplete — it keeps what arrived instead of losing it | `brain/cut.ex` |
| `Line` | the wait queue per capacity (ticket, parked operation) | `brain/line.ex` |
| `AiBudget` | ceiling per category (daily text, monthly per provider) | `ai_budget/policy.ex` |
| `AiActivity` | operation, events and evidence of each execution | `ai_activity/` |
| `Rehearsal` | free fixtures in dev: the call exists, the model does not run | `brain/engines/rehearsal.ex` |

The DeepSeek adapter (`brain/engines/deepseek.ex`) is the closest to what we
need: OpenAI-compatible API, **no retry** (a paid retry is a second charge), a
forced tool with `strict: true` for a structured response, cost in micros,
`status/0` without spending a token.

## 2. What the board needs

No new autonomous agent: the board needs **three things** and they are small if
the contracts above are respected.

1. **A port** (`AgentBoard.AI`) with a literal registry — no prompt loose in the
   code.
2. **The intake**: free request → refined spec → N tasks.
3. **The proof of each call**: one row per call, visible in the board, with cost
   and latency.

## 3. Proposed architecture

```
lib/agent_board/ai.ex                 the port: call(name, inputs, opts)
lib/agent_board/ai/registry.ex        the literal list (the prompt is code)
lib/agent_board/ai/request.ex         model, system, prompt, caps, schema, tier
lib/agent_board/ai/result.ex          text, json, tokens, cost, latency
lib/agent_board/ai/engine.ex          behaviour: run/1, status/0
lib/agent_board/ai/engines/deepseek.ex   OpenAI-compatible (flash + pro)
lib/agent_board/ai/engines/gemini.ex     (to be confirmed: "GM")
lib/agent_board/ai/engines/router.ex     tier + budget + health
lib/agent_board/ai/budget.ex             daily/monthly ceiling, in micros
lib/agent_board/ai/cache.ex              identical response reused
lib/agent_board/ai/call.ex               the table row (Ecto)
priv/repo/migrations/*_create_ai_calls.exs

lib/agent_board/intake.ex                request → spec
lib/agent_board/intake/split.ex          spec → tasks
```

Table `ai_calls`: `name`, `engine`, `model`, `status`, `input_tokens`,
`output_tokens`, `cost_micros`, `duration_ms`, `parse_state`, `json`,
`error`, `inserted_at`. It is the source of the board and of the budget.

### The flow of a call

```
call(:refine_request, %{text: "..."}, tier: :fast)
  → Registry.fetch(:refine_request)          # does it exist? which prompt?
  → Budget.check(tier)                       # does it fit the ceiling?
  → Cache.get(hash)                          # identical response?
  → Router.pick(tier)                        # which engine?
  → Engine.run(%Request{})                   # one request
  → Call.record(...)                         # the row, with cost
  → {:ok, %Result{}}
```

A paid call **always** becomes a row. No row, no payment: it is the rule that
prevents invisible cost.

## 4. The intake (what the user asked for)

Two registered calls, both in the fast tier:

Editorial note: the examples below illustrate a single documentation task; they
are not real outputs. Enumerated values use a valid option, and the first task
does not depend on itself. The architecture around them remains historical.

**`:refine_request`** — receives the raw request and returns JSON:

```json
{
  "goal": "Corrigir links locais quebrados na documentação",
  "constraints": ["Preservar o conteúdo técnico existente"],
  "non_goals": ["Alterar o código da aplicação"],
  "risks": [],
  "open_questions": [],
  "assumptions": [],
  "ready": true,
  "language": "pt"
}
```

Prompt rule: do not invent a requirement. Whatever is missing goes in
`open_questions`, not in an assumption.

**`:propose_tasks`** — receives the refined spec and returns a list:

```json
{
  "tasks": [
    {
      "title": "Corrigir links locais da documentação",
      "body": "Check the link targets under docs/ and fix the broken paths, preserving the technical content.",
      "kind": "docs",
      "acceptance": ["Every local link under docs/ resolves to an existing target"],
      "depends_on": [],
      "size": "S"
    }
  ]
}
```

Rules: each task closes on its own; a dependency only when there is a real order;
`size` L is almost always two tasks. The prompt asks the list to cover the goal;
local validation discards tasks without a title, body or acceptance criteria.

### The pipeline

```
free text
  → :refine_request        (JSON validated by the schema; runs outside the LiveView process)
  → ready=false?           (show questions and an answer box; the answer enters the
                            request as "Respostas:" and the answered text is split again)
  → :propose_tasks         (validated list; depends_on is an index)
  → local validation       (discards a task without a title, body or acceptance)
  → empty list?            (say nothing usable was proposed; offer to try again
                            or send as a single request)
  → human review           (the person marks which tasks enter)
  → Board.create_request   (one issue per marked task; the request key avoids the second
                            issue on a double click, reload or retry; the receipt lists what
                            entered, what was already there and what failed, with a retry
                            only for what failed)
```

The composer (`AgentBoardWeb.BoardComponents.Composer`) is a view of this cycle,
with one job at a time: `dividindo`, `criando`, the proposal (`ready`,
`needs_clarification`, `no_tasks`), a failure with a reason and a try-again
button, and the receipt. A late or canceled result does not find the job by its
`ref` and changes nothing; a timeout (`:composer_timeout_ms`, 60 s) becomes a
named failure. The AI failure appears in words (`fora do formato esperado`
[unexpected format], `sem cota` [no quota], `HTTP 500`), never as `inspect/1`.
The tests use the `AgentBoard.AI.Engines.Scripted` engine (`test/support`) for
deterministic responses: malformed, slow, with questions or empty.

The same pipeline serves **evaluation**: the response is the `(spec, tasks)` pair
that the human reviews before creating.

## 5. Tiers, cost and speed

| Tier | Model | For what | Target latency |
|---|---|---|---|
| `:fast` | `deepseek-flash` | refine, split, classify, summarize | < 3 s |
| `:deep` | `deepseek-v4-pro` | ambiguous spec, difficult decision | < 20 s |

The rule: **fast is the default**. The router moves up to `:deep` only when the
fast result itself signals ambiguity (`open_questions` not empty and `size: L`),
never out of habit.

Budget: a daily ceiling in micros per tier, checked before the call.
`deepseek-flash` fits in cents per ten refinements.

## 6. Guardrails

- **Registry**: an unregistered call does not run. The prompt comes from the code.
- **Schema**: the response is validated; `partial` is kept, not discarded.
- **Input cap**: the input text is cut before spending.
- **Budget**: daily ceiling; when it is crossed, the board says so, it does not
  try to hide it.
- **No paid retry**: a retry is a second charge.
- **Rehearsal in dev**: free fixtures, so the pipeline runs without a key.
- **Fallback**: engine down → `{:error, :unavailable}`, and the UI shows it; never
  an invented response.

## 7. Phases

1. **Foundation** — `AI`, `Registry`, `Request/Result`, `Engine`, `DeepSeek`, the
   `ai_calls` table, tests with `Req.Test` and `Rehearsal`. No UI.
2. **Intake** — `:refine_request`, `:propose_tasks`, validation, `Intake.run/1`,
   task creation by `Board.create_task`.
3. **UI** — the "AI" panel (the latest calls with cost and latency) and the
   "Split this request" button on the board, with the result before creating.
4. **Router + Gemini + budget + cache** — the second engine, the ceiling, the cache.
5. **Voice and conversation** — `Voice.summary` becomes an AI call; the board's
   conversation can ask the model instead of only commenting on GitHub.

Each phase is a PR with a green gate; phase 2 is the one that delivers what the
request describes.

## 8. Evaluation cases (the tasks for testing the intake)

Each case is a raw request, the way it arrives, and what the output must prove.

| # | Raw request | What the output must prove |
|---|---|---|
| 1 | "o board ta lento e as vezes nao carrega" (the board is slow and sometimes does not load) | a spec with a performance `goal`; 2–4 tasks (measure, fix, prove); no "optimize everything" |
| 2 | "queria falar com o agente por voz e ele responder" (I wanted to talk to the agent by voice and have it answer) | separates speech capture, sending and the spoken answer; `open_questions` asks about browser permission |
| 3 | "faz o painel ficar bonito" (make the board pretty) | **refuses to refine without scope**: `open_questions` asks what is ugly; it does not generate 10 generic tasks |
| 4 | "cria as tasks do PR 134 e do 135" (create the tasks for PR 134 and 135) | understands they are two distinct PRs; correct `depends_on` |
| 5 | "não sei, só quero que funcione" (I don't know, I just want it to work) | `open_questions` with 1–3 concrete questions; no invented task |

Cases 3 and 5 are the most important: they prove that the intake **does not
invent**. A pipeline that always returns tasks is worse than one that asks.

## 9. Open decisions

- **"GM"**: is it Gemini? `o_colmex` today has Claude CLI, Codex CLI and DeepSeek.
  If it is Gemini, the adapter is OpenAI-compatible too and enters phase 4.
- **Keys**: does `DEEPSEEK_API_KEY` already exist in the runner's environment?
  The board needs its own.
- **Where the AI lives**: in the board (Elixir, synchronous, visible latency) or
  in the runner (TS, asynchronous)? The proposal is in the board for the intake,
  because the result must appear before it becomes an issue.
- **Ceiling**: what daily budget makes sense for the board?
