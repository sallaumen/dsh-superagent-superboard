# A camada de IA do painel — proposta histórica

> **Registro histórico:** proposta de 5 de novembro de 2026, anterior à
> implementação da camada de IA. O texto abaixo preserva o diagnóstico, as
> projeções e as fases daquela proposta; não descreve o estado atual nem uma
> lista de tarefas ainda pendentes. As referências ao `o_colmex` são o
> levantamento da época, não um inventário verificado por este repositório.
> Para trabalhar na implementação, consulte as [regras de IA](maintainer-contract.md#ai-calls)
> e os pontos de entrada [AgentBoard.AI](../lib/agent_board/ai.ex) e
> [AgentBoard.Intake](../lib/agent_board/intake.ex).

O painel hoje **espelha** o trabalho do agente: sincroniza o GitHub, mostra o
board, fala o resumo. Ele não **chama** modelo nenhum. O `ask` é um comentário
no GitHub; o `Voice` é um template. Este documento mapeia o que falta para o
painel ter uma camada de IA própria — curta, barata e transparente — e o que
dela se aproveita do `o_colmex`, que já resolveu esse problema.

## 1. O que o `o_colmex` já tem

| Contrato | O que faz | Arquivo |
|---|---|---|
| `Engine` (behaviour) | o port para um modelo: `run/1` e `status/0`; um adapter por engine, Mox nos testes | `lib/colmex/brain/engine.ex` |
| `Request` / `Result` | entrada (modelo, system, prompt, caps, schema, tier, rota) e saída (texto, json, tokens, custo em micros, `parse_state`) | `brain/request.ex`, `brain/result.ex` |
| `Registry` | **lista literal das chamadas permitidas**; o prompt é código, um worker não inventa prompt | `brain/registry.ex` |
| `Router` | escolhe a engine por `tier`, quota restante e `recommended`; troca só em resposta definitiva | `brain/engines/router.ex` |
| `Providers` | catálogo: engine, pool, modelo por tier, preços, capacidades | `brain/providers.ex` |
| `Cut` | a resposta paga que veio incompleta — guarda o que veio em vez de perder | `brain/cut.ex` |
| `Line` | a fila de espera por capacidade (ticket, operação parqueada) | `brain/line.ex` |
| `AiBudget` | teto por categoria (texto diário, mensal por provedor) | `ai_budget/policy.ex` |
| `AiActivity` | operação, eventos e evidência de cada execução | `ai_activity/` |
| `Rehearsal` | fixtures grátis em dev: a chamada existe, o modelo não roda | `brain/engines/rehearsal.ex` |

O adapter do DeepSeek (`brain/engines/deepseek.ex`) é o mais próximo do que
precisamos: API OpenAI-compatible, **sem retry** (um retry pago é uma segunda
cobrança), tool forçada com `strict: true` para resposta estruturada, custo em
micros, `status/0` sem gastar token.

## 2. O que o painel precisa

Nada de agente autônomo novo: o painel precisa de **três coisas** e elas são
pequenas se os contratos acima forem respeitados.

1. **Uma porta** (`AgentBoard.AI`) com um registry literal — sem prompt solto
   pelo código.
2. **O intake**: pedido livre → spec refinada → N tasks.
3. **A prova de cada chamada**: uma linha por chamada, visível no painel, com
   custo e latência.

## 3. Arquitetura proposta

```
lib/agent_board/ai.ex                 a porta: call(name, inputs, opts)
lib/agent_board/ai/registry.ex        a lista literal (prompt é código)
lib/agent_board/ai/request.ex         modelo, system, prompt, caps, schema, tier
lib/agent_board/ai/result.ex          texto, json, tokens, custo, latência
lib/agent_board/ai/engine.ex          behaviour: run/1, status/0
lib/agent_board/ai/engines/deepseek.ex   OpenAI-compatible (flash + pro)
lib/agent_board/ai/engines/gemini.ex     (a confirmar: "GM")
lib/agent_board/ai/engines/router.ex     tier + orçamento + saúde
lib/agent_board/ai/budget.ex             teto diário/mensal, em micros
lib/agent_board/ai/cache.ex              resposta idêntica reusada
lib/agent_board/ai/call.ex               a linha da tabela (Ecto)
priv/repo/migrations/*_create_ai_calls.exs

lib/agent_board/intake.ex                pedido → spec
lib/agent_board/intake/split.ex          spec → tasks
```

Tabela `ai_calls`: `name`, `engine`, `model`, `status`, `input_tokens`,
`output_tokens`, `cost_micros`, `duration_ms`, `parse_state`, `json`,
`error`, `inserted_at`. É a fonte do painel e do orçamento.

### O fluxo de uma chamada

```
call(:refine_request, %{text: "..."}, tier: :fast)
  → Registry.fetch(:refine_request)          # existe? qual prompt?
  → Budget.check(tier)                       # cabe no teto?
  → Cache.get(hash)                          # resposta idêntica?
  → Router.pick(tier)                        # qual engine?
  → Engine.run(%Request{})                   # uma requisição
  → Call.record(...)                         # a linha, com custo
  → {:ok, %Result{}}
```

Uma chamada paga **sempre** vira linha. Sem linha, sem pagamento: é a regra que
impede o custo invisível.

## 4. O intake (o que o usuário pediu)

Duas chamadas registradas, ambas de tier rápido:

Nota editorial: os exemplos abaixo ilustram uma única tarefa de documentação;
não são saídas reais. Valores enumerados usam uma opção válida, e a primeira
tarefa não depende de si mesma. A arquitetura ao redor continua sendo histórica.

**`:refine_request`** — recebe o pedido cru e devolve JSON:

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

Regra do prompt: não inventar requisito. O que faltar vai em
`open_questions`, não em suposição.

**`:propose_tasks`** — recebe a spec refinada e devolve uma lista:

```json
{
  "tasks": [
    {
      "title": "Corrigir links locais da documentação",
      "body": "Verificar os destinos dos links em docs/ e corrigir os caminhos quebrados, preservando o conteúdo técnico.",
      "kind": "docs",
      "acceptance": ["Todos os links locais em docs/ resolvem para destinos existentes"],
      "depends_on": [],
      "size": "S"
    }
  ]
}
```

Regras: cada task fecha sozinha; dependência só quando há ordem real; `size` L
quase sempre é duas tasks. O prompt pede que a lista cubra o objetivo; a
validação local descarta tarefas sem título, corpo ou critérios de aceitação.

### O pipeline

```
texto livre
  → :refine_request        (JSON validado pelo schema)
  → ready=false?           (mostrar perguntas; parar sem propor tarefas)
  → :propose_tasks         (lista validada; depends_on é índice)
  → validação local        (descarta task sem título, body ou acceptance)
  → lista vazia?           (informar que nada utilizável foi proposto; permitir novo Split)
  → revisão humana         (a UI só oferece Create para propostas prontas)
  → Board.create_task      (uma issue por ação Create)
```

O mesmo pipeline serve para **avaliar**: a resposta é o par
`(spec, tasks)` que o humano revisa antes de criar.

## 5. Tiers, custo e velocidade

| Tier | Modelo | Para quê | Latência alvo |
|---|---|---|---|
| `:fast` | `deepseek-flash` | refinar, dividir, classificar, resumir | < 3 s |
| `:deep` | `deepseek-v4-pro` | spec ambígua, decisão difícil | < 20 s |

A regra: **o rápido é o padrão**. O roteador sobe para `:deep` só quando o
próprio resultado do rápido sinaliza ambiguidade (`open_questions` não vazio e
`size: L`), nunca por hábito.

Orçamento: um teto diário em micros por tier, checado antes da chamada. O
`deepseek-flash` cabe em centavos por dezena de refinações.

## 6. Guardrails

- **Registry**: chamada não registrada não roda. O prompt vem do código.
- **Schema**: a resposta é validada; `partial` é guardado, não descartado.
- **Input cap**: o texto de entrada é cortado antes de gastar.
- **Budget**: teto diário; ao estourar, o painel diz isso, não tenta esconder.
- **Sem retry pago**: um retry é uma segunda cobrança.
- **Rehearsal em dev**: fixtures grátis, para o pipeline rodar sem chave.
- **Fallback**: engine fora → `{:error, :unavailable}`, e a UI mostra; nunca
  uma resposta inventada.

## 7. Fases

1. **Fundação** — `AI`, `Registry`, `Request/Result`, `Engine`, `DeepSeek`,
   tabela `ai_calls`, testes com `Req.Test` e `Rehearsal`. Sem UI.
2. **Intake** — `:refine_request`, `:propose_tasks`, validação, `Intake.run/1`,
   criação das tasks pelo `Board.create_task`.
3. **UI** — o painel "AI" (as últimas chamadas com custo e latência) e o botão
   "Split this request" no board, com o resultado antes de criar.
4. **Router + Gemini + budget + cache** — a segunda engine, o teto, o cache.
5. **Voz e conversa** — `Voice.summary` vira chamada de IA; a conversa do
   board pode perguntar ao modelo em vez de só comentar no GitHub.

Cada fase é um PR com gate verde; a fase 2 é a que entrega o que o pedido
descreve.

## 8. Casos de avaliação (as tasks para testar o intake)

Cada caso é um pedido cru, do jeito que ele chega, e o que a saída precisa
provar.

| # | Pedido cru | O que a saída precisa provar |
|---|---|---|
| 1 | "o board ta lento e as vezes nao carrega" | spec com `goal` de performance; 2–4 tasks (medir, corrigir, provar); nada de "otimizar tudo" |
| 2 | "queria falar com o agente por voz e ele responder" | separa captura de fala, envio e resposta falada; `open_questions` pergunta sobre permissão do browser |
| 3 | "faz o painel ficar bonito" | **recusa refinar sem escopo**: `open_questions` pergunta o que está feio; não gera 10 tasks genéricas |
| 4 | "cria as tasks do PR 134 e do 135" | entende que são dois PRs distintos; `depends_on` correto |
| 5 | "não sei, só quero que funcione" | `open_questions` com 1–3 perguntas concretas; nenhuma task inventada |

O caso 3 e o 5 são os mais importantes: provam que o intake **não inventa**.
Um pipeline que sempre devolve tasks é pior que um que pergunta.

## 9. Decisões abertas

- **"GM"**: é Gemini? O `o_colmex` hoje tem Claude CLI, Codex CLI e DeepSeek.
  Se for Gemini, o adapter é OpenAI-compatible também e entra na fase 4.
- **Chaves**: `DEEPSEEK_API_KEY` já existe no ambiente do runner? O painel
  precisa da dele.
- **Onde a IA mora**: no painel (Elixir, síncrono, latência visível) ou no
  runner (TS, assíncrono)? A proposta é no painel para o intake, porque o
  resultado precisa aparecer antes de virar issue.
- **Teto**: qual o orçamento diário que faz sentido para o painel?
