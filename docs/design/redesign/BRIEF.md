# BRIEF original — Refinar o design do Agent Board (painel operacional do agente)

## 1. O que é o produto

O Agent Board é um painel local (Phoenix LiveView, roda em 127.0.0.1:4099) que opera um agente de código
(DeepSeek Super Agent) que vive no GitHub. O agente observa issues e comentários com menção, pega o trabalho,
roda numa worktree isolada e abre PR. O board:

- espelha o GitHub a cada 5 min (issues, PRs, reviews, checks, comentários);
- lê os tickets do agente a cada 10 s (estado ao vivo: rodando, pronto, bloqueado);
- deixa o dono criar, parar, arquivar e retomar tarefas;
- despacha executores locais (Claude Code e Codex) com teto de gasto;
- conversa por voz (criar, perguntar, parar tarefas com confirmação falada);
- mostra o custo de cada executor, na moeda de cada um, nunca somado.

Uso: um dono, uma máquina, 1–2 repositórios, sempre aberto. É um instrumento operacional — não é landing page,
não é dashboard de marketing.

## 2. Princípios de design (restrições)

1. Instrumento: preciso, denso mas calmo; zero decoração sem função. Nada de hero, cards aninhados, gradiente
   decorativo, emoji como ícone, "AI slop".
2. Honestidade de dado: o board diz "Ao vivo", "Atrasado", "Sem conexão", "Reconectando", "Sem dados ainda";
   valores são medidos, estimados (≥) ou desconhecidos (—), nunca zero para o desconhecido. O design deve tornar
   esses estados óbvios, não escondê-los.
3. Movimento explica mudança de estado; nunca bloqueia ação; dado que chega por broadcast não reanima. Reduced
   motion desliga tudo mantendo o feedback.
4. Copy em português do Brasil: curta, ativa, sem jargão; erro nomeia causa e recuperação.
5. Acessibilidade: contraste ≥ 4.5, foco visível, ordem de tab conforme a leitura, estados
   vazio/carregando/erro/desabilitado desenhados.
6. Responsivo: 390, 768, 1366, 1920 e 2560. Em telas largas a largura é usada (o layout ocioso colapsa as raias
   numa linha e dá o histórico abaixo).
7. Stack de implementação: Phoenix LiveView + HEEx + Tailwind/daisyUI, com tokens CSS (tema claro e escuro).

## 3. Mapa das telas e menus (o que existe hoje)

### 3.1 Board principal (por repositório)
- Topo: dono/repositório, selo de sincronia clicável ("Ao vivo" / "Atrasado dados de HH:MM · há N min" /
  "Sem conexão" / "Reconectando" / "Sem dados ainda") com popover de detalhes; ações "Dividir pedido" e
  "Novo pedido (N)".
- Objetivo (quando um pedido dividido gerou mais de uma tarefa): título, critério de pronto,
  "x de y tarefas mescladas", barra de progresso.
- Resumo do dia: feito, falhas e pendências, o que o board fez sozinho, gasto por executor
  (DeepSeek / Claude Code / Codex em moedas separadas), botão "Dispensar".
- Aviso de dados parados: "Mostrando o que sabíamos às HH:MM…" + "Tentar agora".
- Vazão por hora: 8 tiles — concluídas, issues abertas, PRs mesclados, commits, tickets encerrados, fila,
  ciclo (issue→PR, PR→merge), paralelismo — com delta, 24 h/7 d e sparkline; fonte não lida aparece "?" com o motivo.
- Raias (a decisão): Agora (execuções em andamento: título, passo, relógio, fases; falhas em nova tentativa),
  Precisa de você (bloqueios, perguntas, revisões, silêncio de execução; ações), Fila (lista numerada, filtros,
  "mais N na fila"), Mesclados (7 dias em pontos + grupos por dia + histórico).
- Estados: ocioso (nada rodando/fila/atenção), vazio (repositório sem dados), cheio (muitas tarefas),
  atrasado/desconectado.

### 3.2 Inspector da tarefa (abre pela raia)
- Cabeçalho: título, número, estado, idade; ações: Perguntar, Parar, Arquivar/Retomar, Tentar de novo,
  Despachar (Claude Code/Codex), Parar execução — todas com frase de confirmação.
- Abas: Conversa (comentários + relatório do agente), Atividade (eventos), Execuções (execuções locais e do
  agente, tokens e custo), PR (revisão, CI, checks).
- Bloco de despacho local: executor, teto, pausa global, confirmação, e a falha classificada com a sugestão
  (repetir/trocar executor).

### 3.3 Composer ("Novo pedido" e "Dividir pedido")
- Texto do pedido, título editável, seletor de executor (DeepSeek/Claude/Codex) com sugestão, motivos e custo
  esperado, revisão do split (tarefas com tipo/tamanho e checkboxes), frase de confirmação e recibo (criadas,
  já estavam na fila, falhas com retry).

### 3.4 Hoje (visão entre repositórios)
- Data local, gasto do dia por executor, "Precisa de você" (itens com o repositório em cada linha),
  "Rodando agora", legenda curta. Uma lista só.

### 3.5 Superagentes DeepSeek
- Lista de agentes por projeto: profile, porta, workers, estado desejado, state dir, última leitura;
  iniciar/parar/pausar/retomar, escala de workers, "Adicionar projeto" (repositório, profile de origem,
  checkout, workers) com revisão/confirmação, arquivar.

### 3.6 Conversa por voz
- Painel com o histórico da conversa, "O que posso pedir" (comandos por grupo: status, execuções, analisar
  tarefa, bugs, busca, pedidos, ajustes), "Bastidores da voz" (cada etapa ao vivo), "Esquecer conversa";
  espaço duplo abre a fala.

### 3.7 Configurações (menu)
- Inspecionar; Despacho local (pausa, tetos mensal/por tarefa/minutos); Voz (entrada Wispr vs microfone do
  board, motor navegador/misto/ElevenLabs, voz, idioma, volume, velocidade, entonação, pausa, chamados de
  atenção, narração, som do microfone, preview, gasto do dia e teto); Resumo do dia (ligar/desligar, horário);
  Repositórios (acompanhar outro); Aparência (claro/escuro); Versão (verificar/atualizar e reiniciar).

### 3.8 Atalhos
- Lista de teclas: espaço duplo (fala), V (voz no composer), N (novo pedido), ? (ajuda), Esc (fechar).
