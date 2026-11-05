# Design pass — Agent Board

Direção: painel escuro, denso, monoespaçado. Refinamento da interface existente,
sem bibliotecas novas, gradientes ou efeitos de vidro. Apenas apresentação em
`lib/agent_board_web/`, tokens/CSS e testes; `lib/agent_board/` não foi alterado.
Todos os handlers, nomes dos eventos, payloads e formulários foram preservados.

## Achados e correções

| Severidade | Região | Evidência | Correção |
|---|---|---|---|
| P2 | Merged | [Antes](before-1600.png), [depois](after-1600.png) | Cinco linhas mais recentes; expansão nativa para os outros 25. A contagem diz “latest 30 loaded”, pois o contexto limita a consulta a 30. Não representa o total do GitHub. |
| P2 | Colunas vazias | [Antes](before-1600.png), [depois](after-1600.png) | Running, Ready, Blocked e Queued em quatro áreas de 100 px quando vazias. O histórico ocupa uma seção independente e não determina sua altura. |
| P2 | Cabeçalho | [Antes](before-1600.png), [depois](after-1600.png) | Identidade, seletor de repositório e configuração separados. Formulário Track repo dentro de uma expansão nativa; saúde e utilitários na segunda linha. |
| P2 | Versão | [Antes](before-1600.png), [depois](after-1600.png); `system_panel.ex:26–63` | Indicador com contorno e cor semântica, hashes em segundo plano. Update & restart usa warning/warning-content quando o backend informa `:behind`. Valor ausente continua “unknown”. |
| P2 | IA | [Depois, página completa](after-full-1600.png); `board_live.ex`, componente `.ai-call-metrics` | Nome da chamada primeiro; provedor/modelo abaixo; resultado, latência e uso separados. Medições ausentes mostram “unknown”; zero armazenado continua zero. |

Os tokens dark base-100/200/300 foram ajustados para grafite mais escuro. Novos
estilos usam apenas os tokens existentes, currentColor e misturas desses tokens.
O tema claro permanece funcional: [screenshot light](after-light-1600.png).
A captura principal usa dados reais já armazenados. A falha de sync e o estado
unknown da versão são respostas reais do backend; não foram escondidos ou simulados.

## Verificação visual e teclado

WebKit headless, uma aba, interações somente de leitura:

- 1600×900: histórico recolhido com cinco linhas; 25 itens acessíveis ao expandir;
  painel de IA começa em y=703 px. Histórico completo recolhido ocupa 288 px.
- Enter abre e fecha Merged e Repositories. Tab após abrir Repositories chega
  ao campo Owner. Contorno de foco computado: solid.
- Light/dark alternam o atributo data-theme e as cores renderizadas.
- Sem overflow horizontal em [1366×768](after-1366.png),
  [3440×1440](after-3440.png) ou [375×812](after-375.png).
- Navegador fechado ao terminar. Nenhum envio, tarefa criada/arquivada, áudio,
  Check ou Update & restart acionado pelo navegador.

A prévia foi executada neste checkout em 127.0.0.1:4003. O serviço launchd usa
outro checkout (`/Users/tavano/src/agent_board`, porta 4099); a prévia não é um
registro de implantação. As imagens foram capturadas antes do commit, por isso
mostram o hash servido anterior e “uncommitted changes”.

## Gate local

Com a CI bloqueada por billing, foi aplicado o procedimento de PIPELINES.md:
`scripts/ci-local.sh all`, exit 0. [Log completo](ci-local.log).

- `MIX_ENV=test mix gate`: dependências, compilação com warnings-as-errors,
  format, Credo e **171 testes, 0 falhas**.
- Sobelow: scan complete, exit 0.
- `scripts/check_assets.sh`: OK; `mix assets.setup`, `mix assets.build` e
  `mix assets.deploy`: exit 0.
- Biblioteca: validador verde; 20 testes, OK.
- Novos testes cobrem limite/ordem/expansão dos merges, histórico vazio e
  métricas ausentes. Os testes existentes cobrem os eventos preservados.

O projeto exige `MIX_ENV=test` ao chamar o alias gate diretamente: a invocação
sem essa variável terminou na proteção de mix test contra execução em dev.
A execução correta acima passou e também foi repetida pelo pipeline completo.

Trecho final de mix gate dentro do pipeline:

```text
344 mods/funs, found no issues.

Use `mix credo explain` to explain issues, `mix credo --help` for options.
Running ExUnit with seed: 676315, max_cases: 28

...........................................................................................................................................................................
Finished in 15.0 seconds (4.1s async, 10.9s sync)
171 tests, 0 failures
```

Quando billing for resolvido, redisparar o workflow conforme PIPELINES.md.
