# Contextos opcionais

Estes arquivos registram intenções e preferências de projetos específicos, descritas na conversa que originou a biblioteca. Eles **não** são regras universais, não provam o estado atual dos repositórios correspondentes e **nunca** são carregados por padrão.

## Regras de uso

1. Carregue um contexto somente quando o projeto correspondente estiver no escopo e somente as seções pertinentes à área em trabalho.
2. Confirme no código o que o contexto afirma; ignore exemplos que não existam no projeto.
3. Um projeto mobile first tradicional (ex.: `forro-mobile`) não herda a estética de jogo do Colmex. Um projeto sem Oban não recebe regras de workers desse framework (`elixir-phoenix-oban`).
4. Adapte um contexto somente quando houver evidência da necessidade; a regra de separação entre núcleo e contexto vale também para contextos novos.

## Dependências

| Contexto | Conteúdo | Dependência |
|---|---|---|
| `colmex/base.md` | Colmex: produto e identidade | Nenhuma |
| `colmex/casas.md` | Ateliê, Prefeitura, Torre e Laboratório | colmex/base.md |
| `colmex/comercio.md` | Mercado, Indústria, fornecedores e Amostras | colmex/base.md |
| `colmex/colmeia.md` | Colmeia e gestão visual de IAs | colmex/base.md |
| `forro-mobile.md` | Forró: mobile first e Programação integrada | Nenhuma |
| `elixir-phoenix-oban.md` | Elixir, Phoenix, LiveView e Oban | Nenhuma |

## Adicionar um contexto novo

Crie o arquivo aqui, registre-o no `manifest.json` (seção `contexts`), declare suas dependências e não o referencie no corpo de nenhuma skill do núcleo. O validador confere dependências e ciclos.
