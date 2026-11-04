# Incorporação: mapa de origem e destino

Origem: **biblioteca-prompts-desenvolvimento v1.0.0** (pacote ZIP de 4 de novembro de 2026). Destino: este repositório, em `capabilities/`.

## Prompts P01–P34

| Origem | Destino | Decisão |
|---|---|---|
| P01 · Coordenar a consolidação do produto por áreas | `skills/coordenar-entregas/SKILL.md` — Workflow A | **Fundido com P02**: mesma mecânica de coordenação (frentes, listener, autorizações); os dois objetivos continuam como workflows distintos com gatilhos próprios. |
| P02 · Planejar entregas, PRs e integração entre frentes | `skills/coordenar-entregas/SKILL.md` — Workflow B | **Fundido com P01** (ver acima). |
| P03 · Revisão arquitetural orientada ao domínio | `skills/revisar-arquitetura/SKILL.md` | Skill própria: limites de domínio; fronteira distinta de P04/P05. |
| P04 · Stratified design e níveis de abstração | `skills/stratified-design/SKILL.md` | Skill própria: perspectiva de níveis de significado; fonte primária em `referencias/fontes-e-conceitos.md`. |
| P05 · Módulos, nomes e APIs internas | `skills/organizar-modulos/SKILL.md` | Skill própria: vocabulário, localização e contratos públicos. |
| P06 · Código inacabado, obsoleto ou sem uso | `skills/consolidar-codigo/SKILL.md` | Skill própria: decidir destino de candidatos com evidência de uso. |
| P07 · Versões, seleção, publicação e rastreabilidade | `skills/versoes-e-rastreabilidade/SKILL.md` | Skill própria: identidade e linhagem de versões ≠ integridade de contratos (P08). |
| P08 · Contratos, fontes de verdade e integridade de dados | `skills/contratos-e-dados/SKILL.md` | Skill própria (ver acima). |
| P09 · Identidade da UI e remoção de AI slop | `skills/identidade-ui/SKILL.md` | Skill própria: identidade e hierarquia visual; fronteira distinta de P10/P11. |
| P10 · Espaços, alinhamentos e densidade | `skills/espaco-e-densidade/SKILL.md` | Skill própria: composição espacial (ver acima). |
| P11 · Experiência completa e navegação | `skills/ux-e-navegacao/SKILL.md` | Skill própria: jornada e continuidade (ver acima). |
| P12 · Experiência mobile e histórico | `skills/mobile-e-responsividade/SKILL.md` — Workflow A | **Fundido com P13**: compartilham matriz de inspeção e evidência (viewport × dispositivo real); os dois critérios permanecem como workflows distintos. |
| P13 · Responsividade e ultrawide | `skills/mobile-e-responsividade/SKILL.md` — Workflow B | **Fundido com P12** (ver acima). |
| P14 · Interações visuais diretas | `skills/interacoes-diretas/SKILL.md` | Skill própria: desenho de interação e persistência confiável. |
| P15 · Acessibilidade | `skills/acessibilidade/SKILL.md` | Skill própria: disciplina com critérios próprios (WCAG em referências). |
| P16 · Design system e instruções | `skills/design-system/SKILL.md` | Skill própria: consolidação de padrões e documentação operacional. |
| P17 · Performance, frame rate e freezes | `skills/performance/SKILL.md` | Skill própria: custo medido ≠ consistência de estado (P18). |
| P18 · Estados assíncronos e tempo real | `skills/estados-assincronos/SKILL.md` | Skill própria (ver acima). |
| P19 · Orquestração de IAs, capacidade e filas | `skills/orquestracao-ias/SKILL.md` | Skill própria: contrato de capacidade e alocação real. |
| P20 · Bots, notificações e excesso de mensagens | `skills/notificacoes-e-bots/SKILL.md` | Skill própria: transporte e entrega ≠ ciclo do alerta (P33). |
| P21 · Configuração de integrações e fornecedores | `skills/setup-integracoes/SKILL.md` | Skill própria: prontidão e setup retomável ≠ elegibilidade da oferta (P22). |
| P22 · Catálogo e elegibilidade comercial | `skills/elegibilidade-comercial/SKILL.md` | Skill própria (ver acima). |
| P23 · Imagens, prévias e rastreabilidade de assets | `skills/assets-e-imagens/SKILL.md` | Skill própria: pipeline de imagem com identidade e ciclo de vida. |
| P24 · Métricas, custos e proveniência | `skills/metricas-e-custos/SKILL.md` | Skill própria: significado, origem e limitações de cada número. |
| P25 · Limpeza de testes duplicados | `skills/testes-redundantes/SKILL.md` | Skill própria: remover redundância ≠ encontrar lacunas (P26). |
| P26 · Estratégia de testes e lacunas | `skills/estrategia-de-testes/SKILL.md` | Skill própria (ver acima). |
| P27 · Code review independente | `skills/code-review/SKILL.md` | Skill própria, modo `revisar`: somente leitura; não autoriza correção nem publicação de comentários. |
| P28 · Investigação de bugs e causa raiz | `skills/investigar-bugs/SKILL.md` | Skill própria: reprodução e hipóteses discriminadas ≠ review (P27). |
| P29 · Segurança, permissões e isolamento | `skills/seguranca-e-permissoes/SKILL.md` | Skill própria: autorização na fronteira real; não autoriza testes ofensivos. |
| P30 · Migrations e compatibilidade entre versões | `skills/migracoes-e-compatibilidade/SKILL.md` | Skill própria: dados que precisam sobreviver à troca de versão. |
| P31 · Dependências, build e CI | `skills/build-ci-dependencias/SKILL.md` | Skill própria: reprodutibilidade sem esconder checks. |
| P32 · Validação da entrega integrada | `skills/validar-entrega/SKILL.md` | Skill própria, modo `analisar`: valida e relata; correções exigem mudança explícita de modo. |
| P33 · Alertas operacionais e ciclo de vida | `skills/alertas-operacionais/SKILL.md` | Skill própria: problema operacional e sua resolução (ver P20). |
| P34 · Jogo, simulação e produção | `skills/simulacao-e-producao/SKILL.md` | Skill própria: isolamento de contexto e efeitos entre ambientes. |

## Base, contextos, templates, scripts e validação

| Origem | Destino | Decisão |
|---|---|---|
| `base/contrato-de-execucao.md` | `contrato.md` | Adaptado: referência a skills em vez de prompts; regras preservadas. |
| `base/parametros-e-modos.md` | `parametros.md` | Adaptado: seção do compositor substituída por "Carregar uma skill manualmente". |
| `base/roteiros-de-uso.md` | `referencias/roteiros-de-uso.md` | IDs substituídos por nomes de skills; seção final reescrita. |
| `base/mapa-das-frentes.md` | `referencias/mapa-das-frentes.md` | IDs substituídos; linha de incorporação aponta para este documento. |
| `contextos/colmex-*.md`, `forro-mobile.md`, `elixir-phoenix-oban.md` | `contextos/` | Preservados como opt-in; lembretes de skills renomeados; regra "nunca carregar por padrão" em `contextos/README.md`. |
| `templates/plano-de-entrega.md`, `registro-de-decisao.md`, `registro-de-diagnostico.md`, `resultado-e-validacao.md` | `templates/` | Preservados sem alteração. |
| `templates/esboco-de-skill.md` | `templates/nova-capacidade.md` | Adaptado ao formato SKILL.md e aos arquivos de registro desta biblioteca. |
| `referencias/fontes-e-conceitos.md` | `referencias/fontes-e-conceitos.md` | Menções atualizadas; fontes primárias preservadas. |
| `manifest.json` | `manifest.json` | Reescrito: schema v2, skills com `origem` (rastreabilidade P01–P34), contextos com dependências. |
| `scripts/compor_prompt.py` | **Descartado** | A composição manual de prompt+contrato+contexto deixa de ser necessária: a IA lê a skill e segue suas referências; o fluxo manual está descrito em `parametros.md`. |
| `scripts/validar_pacote.py` + `scripts/_biblioteca.py` | `tools/validar_biblioteca.py` | Substituídos por validador adaptado ao formato de skills (frontmatter, manifesto, origem→destino, contextos, links). |
| `validacao/testar_ferramentas.py` | `tools/test_validar_biblioteca.py` | Substituído; testes reescritos para o validador novo (15 testes). |
| `validacao/casos-de-avaliacao.{md,json}` | `validacao/` | Nomes de skills atualizados; 3 casos novos (E25 UI sem contexto de jogo, E26 sem ferramenta de delegação, E27 ação externa sem autorização). |
| `validacao/fixture-code-review/*` | `validacao/fixtures/code-review/*` | Reutilizados para revalidar o cenário controlado de code review nesta edição. |
| `validacao/relatorio-de-revisao.md`, `resultado-roteamento.json`, `resultado-code-review.md`, `verificacoes-automatizadas.json` | **Descartados** | Evidência da edição de origem (v1.0.0), não desta incorporação; substituídos por `validacao/relatorio-de-validacao.md`, que cita os achados da origem. |
| `README.md`, `CATALOGO.md` | `README.md`, `CATALOGO.md` | Reescritos para a estrutura de skills. |
| `99-incorporar-biblioteca-ao-projeto.md` | **Descartado** | Era o pedido de incorporação; consumido por esta tarefa. |

## Decisões de fronteira preservadas

- **Análise ≠ correção ≠ revisão ≠ coordenação**: os modos do contrato são herdados por todas as skills; `code-review` permanece somente leitura e `validar-entrega` não corrige por padrão.
- **Arquitetura**: P03 (limites do domínio), P04 (níveis de abstração) e P05 (nomes/APIs) ficaram separados — são perspectivas relacionadas com gatilhos e critérios diferentes; cada descrição roteia para a vizinha correta.
- **UI**: P09 (identidade), P10 (espaço) e P11 (jornada) ficaram separados; P12+P13 foram fundidos porque compartilham a técnica de evidência e os roteiros as usam juntas, mantendo os dois critérios como workflows.
- **Testes**: P25 (redundância) e P26 (lacunas) ficaram separados; remover proteção não é procurar proteção nova.
- **Revisão de diff**: `code-review` não autoriza alterar o trabalho sob revisão; P27 e P28 separados (review de mudança × investigação causal).
- **Operação**: P17×P18 (custo × estado), P20×P33 (transporte × ciclo do alerta), P21×P22 (setup × elegibilidade) ficaram separados — cada par confunde usuários e o catálogo registra o critério de escolha.
- **Coordenação**: limite padrão de duas frentes, listener/espera quando disponível e queda para execução sequencial sem delegação — regra no contrato comum e nos workflows de `coordenar-entregas`.

## O que já existia neste repositório

Nenhuma estrutura de skills, prompts ou contextos existia antes em `agent-board`. `AGENTS.md` e `README.md` do repositório ganharam apenas ponteiros curtos para esta biblioteca (sem copiar conteúdo). As capacidades da sessão atual do agente (skills instaladas no perfil do harness, como `ui-review` ou `ripwire-*`) continuam separadas desta biblioteca: são mecanismos do ambiente, não deste repositório.

## Limitações desta incorporação

- Nenhuma skill foi instalada ou verificada em um agente específico (Claude Code, DSH, etc.); a compatibilidade de formato segue a especificação documentada de Agent Skills, sem teste de instalação em cada plataforma.
- Os contextos de Colmex, forró e Elixir registram intenções relatadas; não foram confrontados com os repositórios reais correspondentes.
- Validação comportamental feita em cenários controlados (ver `validacao/relatorio-de-validacao.md`); uso em projeto real é trabalho posterior.
