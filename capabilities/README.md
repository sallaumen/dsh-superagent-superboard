# Biblioteca de capacidades de desenvolvimento

Capacidades reutilizáveis de desenvolvimento para uso entre projetos: workflows de arquitetura, produto, UI, UX, testes, revisão de código, integrações e operação, organizados como skills pequenas com referências carregadas sob demanda.

Origem: **biblioteca-prompts-desenvolvimento v1.0.0** (34 prompts-fonte), analisada e reorganizada conforme [INCORPORACAO.md](INCORPORACAO.md).

## Como uma IA usa esta biblioteca

1. **Descubra a capacidade** pelo resultado desejado: leia [CATALOGO.md](CATALOGO.md) ou o campo `description` do frontmatter de cada `skills/<nome>/SKILL.md`.
2. **Carregue a skill escolhida** e o [contrato comum](contrato.md), que vale para todas. Use [parametros.md](parametros.md) para delimitar modo, escopo e entradas.
3. **Carregue referências somente quando necessário**: as instruções extensas já estão na própria skill; [referencias/](referencias/roteiros-de-uso.md) contém sequências por problema e fontes conceituais.
4. **Carregue um contexto apenas se o projeto correspondente estiver no escopo** — leia [contextos/README.md](contextos/README.md) antes. Nenhum contexto é carregado por padrão.
5. **Registre decisões e resultados** com os modelos em [templates/](templates/plano-de-entrega.md) quando a tarefa justificar.

As regras de execução, autonomia, autorização e validação têm uma única
referência normativa: o [contrato comum](contrato.md).

## Estrutura

```
capabilities/
├── README.md            # este arquivo
├── CATALOGO.md          # catálogo com sinais de uso, modos e relacionadas
├── INCORPORACAO.md      # mapa completo de origem e destino + decisões
├── manifest.json        # índice estruturado para outras IAs e ferramentas
├── contrato.md          # contrato comum de execução (núcleo)
├── parametros.md        # modos, parâmetros e regras de contexto
├── skills/<nome>/SKILL.md   # uma entrada pequena por capacidade
├── referencias/         # roteiros de uso e fontes conceituais
├── contextos/           # adaptadores opcionais (Colmex, forró, Elixir)
├── templates/           # modelos de entrega, decisão, diagnóstico e validação
├── tools/               # validador determinístico e seus testes
└── validacao/           # cenários de avaliação, fixtures e relatório
```

## Adicionar uma nova capacidade sem duplicar instruções

1. Confirme que a necessidade é real e a fronteira é diferente das existentes: compare com o catálogo e com as dúvidas comuns de escolha. Prefira um workflow novo dentro de uma skill existente a criar outra quando a diferença for só uma variação.
2. Crie `skills/<nome>/SKILL.md` com o frontmatter (`name`, `title`, `category`, `default_mode`, `origem`, `related`, `description` com os sinais de uso) e um corpo com `## Quando usar`, `## Entradas úteis` e `## Instrução`. Mantenha o corpo no essencial; coloque detalhes extensos em `referencias/` e carregue-os sob condição.
3. Não repita o contrato comum nem os contextos dentro da skill: referencie `contrato.md` e aponte os contextos pertinentes sem copiá-los.
4. Registre a skill no `manifest.json`, o destino da origem no [INCORPORACAO.md](INCORPORACAO.md), a linha no [CATALOGO.md](CATALOGO.md) e um caso de avaliação em [validacao/casos-de-avaliacao.json](validacao/casos-de-avaliacao.json) (positivo, vizinho de outra skill e pedido pequeno que não ativa nada).
5. Use [templates/nova-capacidade.md](templates/nova-capacidade.md) como roteiro de planejamento.

## Manter contextos separados do núcleo

As regras de seleção, separação do núcleo e registro de dependências ficam em
[contextos/README.md](contextos/README.md). Siga esse contrato ao usar ou adicionar
um contexto.

## Validar

Os comandos, pré-requisitos, códigos de saída e instruções para adoção em
outro projeto estão em [tools/README.md](tools/README.md). As ferramentas
validam a estrutura da biblioteca; não executam as skills.

Cenários comportamentais de roteamento e limites estão em [validacao/casos-de-avaliacao.md](validacao/casos-de-avaliacao.md); a evidência (histórica) da incorporação está em [validacao/relatorio-de-validacao.md](validacao/relatorio-de-validacao.md).

## Ambientes suportados

As skills usam o formato de pasta `SKILL.md` com frontmatter `name`/`description`, documentado na [especificação de Agent Skills](https://agentskills.io/specification). Esta biblioteca **não** foi instalada em nenhum agente específico nem verificada em múltiplas plataformas; a validação desta edição cobre formato, integridade de referências e cenários controlados com um executor que lê arquivos. A instalação em um agente (ex.: catálogo de skills de uma sessão) é trabalho separado e deve ser verificada no ambiente correspondente.
