# Original BRIEF — Refining the Agent Board design (the agent's operational panel)

## 1. What the product is

The Agent Board is a local panel (Phoenix LiveView, runs at 127.0.0.1:4099) that operates a coding agent
(DeepSeek Super Agent) that lives on GitHub. The agent watches issues and comments that mention it, takes the
work, runs in an isolated worktree and opens a PR. The board:

- mirrors GitHub every 5 min (issues, PRs, reviews, checks, comments);
- reads the agent's tickets every 10 s (live state: running, ready, blocked);
- lets the owner create, stop, archive and resume tasks;
- dispatches local executors (Claude Code and Codex) with a spending ceiling;
- talks by voice (create, ask, stop tasks with spoken confirmation);
- shows each executor's cost, in each one's currency, never summed.

Usage: one owner, one machine, 1–2 repositories, always open. It is an operational instrument — not a landing
page, not a marketing dashboard.

## 2. Design principles (constraints)

1. Instrument: precise, dense but calm; zero decoration without function. No hero, nested cards, decorative
   gradient, emoji as icons, "AI slop".
2. Data honesty: the board says "Ao vivo" (Live), "Atrasado" (Delayed), "Sem conexão" (No connection),
   "Reconectando" (Reconnecting), "Sem dados ainda" (No data yet); values are measured, estimated (≥) or
   unknown (—), never zero for unknown. The design must make these states obvious, not hide them.
3. Motion explains a state change; it never blocks an action; data arriving by broadcast does not re-animate.
   Reduced motion turns everything off while keeping the feedback.
4. Copy in Brazilian Portuguese: short, active, no jargon; an error names the cause and the recovery.
5. Accessibility: contrast ≥ 4.5, visible focus, tab order follows reading order, empty/loading/error/disabled
   states designed.
6. Responsive: 390, 768, 1366, 1920 and 2560. On wide screens the width is used (the idle layout collapses the
   lanes into one row and puts the history below).
7. Implementation stack: Phoenix LiveView + HEEx + Tailwind/daisyUI, with CSS tokens (light and dark theme).

## 3. Screen and menu map (what exists today)

### 3.1 Main board (per repository)
- Top: owner/repository, clickable sync badge ("Ao vivo" / "Atrasado dados de HH:MM · há N min" /
  "Sem conexão" / "Reconectando" / "Sem dados ainda") with a details popover; actions "Dividir pedido"
  (Split request) and "Novo pedido (N)" (New request).
- Objective (when a split request produced more than one task): title, definition of done,
  "x de y tarefas mescladas" (x of y tasks merged), progress bar.
- Day summary: done, failures and pending items, what the board did on its own, spend per executor
  (DeepSeek / Claude Code / Codex in separate currencies), "Dispensar" (Dismiss) button.
- Stale data notice: "Mostrando o que sabíamos às HH:MM…" (Showing what we knew at HH:MM…) + "Tentar agora"
  (Try now).
- Vazão por hora (Hourly throughput): 8 tiles — completed, open issues, merged PRs, commits, closed tickets,
  queue, cycle (issue→PR, PR→merge), parallelism — with delta, 24 h/7 d and sparkline; an unread source shows
  "?" with the reason.
- Lanes (the decision): Agora (Now; running executions: title, step, clock, phases; failures on retry),
  Precisa de você (Needs you; blocks, questions, reviews, execution silence; actions), Fila (Queue; numbered
  list, filters, "mais N na fila" (more N in the queue)), Mesclados (Merged; 7 days as dots + groups by day +
  history).
- States: idle (nothing running/queued/needing attention), empty (repository with no data), full (many tasks),
  stale/disconnected.

### 3.2 Task inspector (opens from the lane)
- Header: title, number, state, age; actions: Perguntar (Ask), Parar (Stop), Arquivar/Retomar
  (Archive/Resume), Tentar de novo (Try again), Despachar (Dispatch; Claude Code/Codex), Parar execução
  (Stop execution) — all with a confirmation sentence.
- Tabs: Conversa (Conversation; comments + agent report), Atividade (Activity; events), Execuções
  (Executions; local and agent runs, tokens and cost), PR (review, CI, checks).
- Local dispatch block: executor, ceiling, global pause, confirmation, and the classified failure with the
  suggestion (retry/switch executor).

### 3.3 Composer ("Novo pedido" and "Dividir pedido")
- Request text, editable title, executor selector (DeepSeek/Claude/Codex) with a suggestion, reasons and
  expected cost, split review (tasks with type/size and checkboxes), confirmation sentence and receipt
  (created, already in the queue, failures with retry).

### 3.4 Hoje (Today; cross-repository view)
- Local date, the day's spend per executor, "Precisa de você" (items with the repository on each line),
  "Rodando agora" (Running now), short legend. A single list.

### 3.5 Superagentes DeepSeek (DeepSeek Super Agents)
- List of agents per project: profile, port, workers, desired state, state dir, last read;
  start/stop/pause/resume, worker scale, "Adicionar projeto" (Add project; repository, source profile,
  checkout, workers) with review/confirmation, archive.

### 3.6 Voice conversation
- Panel with the conversation history, "O que posso pedir" (What I can ask; commands by group: status,
  executions, analyze task, bugs, search, requests, adjustments), "Bastidores da voz" (Voice backstage; each
  step live), "Esquecer conversa" (Forget conversation); double space opens speech.

### 3.7 Configurações (Settings; menu)
- Inspecionar (Inspect); Despacho local (Local dispatch; pause, monthly/per-task/minute ceilings); Voz (Voice;
  Wispr input vs board microphone, browser/mixed/ElevenLabs engine, voice, language, volume, speed,
  intonation, pause, attention calls, narration, microphone sound, preview, the day's spend and ceiling);
  Resumo do dia (Day summary; on/off, time); Repositórios (Repositories; track another); Aparência
  (Appearance; light/dark); Versão (Version; check/update and restart).

### 3.8 Shortcuts
- Key list: double space (speech), V (voice in the composer), N (new request), ? (help), Esc (close).
