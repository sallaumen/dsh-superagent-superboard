# Revisão e integração dos quatro PRs

> **Registro histórico — 5 de novembro de 2026.** Contagens, capturas e estados
> descrevem as revisões identificadas neste documento, não o produto atual.
> Consulte o [índice e a sequência da auditoria](README.md).

Sequência de dependências: #154 → #158 → #161 → #164. Os PRs seguintes tiveram a
base alterada para `main` após a integração da dependência. Foram preservados os
novos provedores, a saída estruturada (#169/#170), a configuração de ambiente e o
painel de versão que entraram em main depois da auditoria original.

## Achados resolvidos na revisão

- **Tokens do SystemPanel:** o componente novo havia reintroduzido cores
  hexadecimais. O #154 inclui a conversão para warning/success/info e respectivos
  tokens de conteúdo. Ações de versão e atualização preservadas; não acionadas
  durante a revisão visual. Evidência em [01-theme](01-theme.md#revisão-para-merge).
- **Documentação de saúde:** #161 atualiza AGENTS.md e README: ausência de sync,
  falha de sync e reconexão têm significados distintos. O README ainda dizia que
  `no sync yet` indicava exceção.
- **Conflito textual no #164:** os eventos `check_version`/`update` adicionados ao
  LiveView colidiam com a nova cláusula `intake` sem IA. Foram mantidos os dois
  eventos e a cláusula de proteção antes do intake normal. Nenhum handler perdido.

## Gates locais

| PR | Código validado | Resultado de scripts/ci-local.sh all |
|---|---|---|
| #154 | `415a732` | 160 testes Elixir, Sobelow, assets e biblioteca verdes |
| #158 | `331c876` | 160 testes Elixir, Sobelow, assets e biblioteca verdes |
| #161 | `ec6fe27` (+ documentação em `26896b1`) | 164 testes Elixir, Sobelow, assets e biblioteca verdes |
| #164 | `5f97600` | 168 testes Elixir, Sobelow, assets e biblioteca verdes |

Cada execução incluiu format/credo/compilação/dependências/testes via mix gate,
scripts/check_assets.sh, assets.build/deploy e os 20 testes da biblioteca.
O main recebeu #169/#170 durante a sequência; o gate cumulativo final inclui ambos.
Os acréscimos posteriores ao gate final são somente este registro e screenshots.

O GitHub confirmou billing na annotation do job 127201135118: o job não iniciou
por falha de pagamento ou limite de gastos. O gate local foi usado conforme
PIPELINES.md e a autorização do usuário; não se esperou nem se redisparou Actions.
Quando billing for liberado, executar workflow_dispatch sobre main.

## WebKit após a resolução

Light/dark em 1366×768, 3440×1440 e 375×812: scrollWidth igual à largura do viewport,
LiveView conectado e painel de versão acima das colunas. Disconnect/connect voltou
`reconnecting → live`. Zero erros ou warnings no console. Sem operações mutáveis,
mensagens, execução de Update & restart ou áudio real. Browser e servidor próprios
encerrados.

Capturas: [1366 claro](merged-review-light-1366.png),
[1366 escuro](merged-review-dark-1366.png),
[3440 claro](merged-review-light-3440.png),
[3440 escuro](merged-review-dark-3440.png),
[375 claro](merged-review-light-375.png), [375 escuro](merged-review-dark-375.png).
