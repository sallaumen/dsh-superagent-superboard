# Parâmetros, modos e contexto

## Uso mínimo

Informe o projeto ou repositório, o escopo e o resultado desejado. O restante pode ser descoberto pela IA. Não é necessário preencher um questionário para começar.

```text
Projeto: meu aplicativo
Escopo: fluxo de catálogo, seleção de variante e pedido de amostra
Objetivo: tornar claros os fornecedores elegíveis e impedir escolhas incompatíveis
Modo: analisar-e-corrigir
Evidências disponíveis: duas imagens, acesso ao código e ambiente local
Restrições: preservar os dados; usar apenas o sandbox do fornecedor
```

Uma pergunta de arquitetura pode usar apenas “Escopo: módulos de pedidos; objetivo: reduzir dependências cruzadas”. Uma revisão de PR deve incluir o diff ou uma referência verificável à base e à mudança. As evidências ausentes são limitações a registrar, não lacunas a preencher com invenção.

## Modos

Escolha o modo conforme [Respeite o modo escolhido](contrato.md#2-respeite-o-modo-escolhido).
Essa seção define os resultados e limites de cada modo, o padrão e a
precedência das instruções da sessão.

## Parâmetros opcionais úteis

| Parâmetro | Quando informar | Padrão sensato |
|---|---|---|
| Área e fluxos | Projeto grande ou vários contextos abertos | Descobrir pelo pedido e declarar o recorte |
| Perfis de usuário | Permissões ou jornadas diferentes | Identificar os papéis que existem no código |
| Ambiente | Há sandbox, staging e produção | Inspecionar antes de executar efeitos |
| Comandos de validação | Projeto tem gates conhecidos | Ler scripts e instruções do repositório |
| Baseline | Há falhas anteriores relevantes | Registrar o estado inicial proporcional ao risco |
| Identidade visual | Há referência ou design system | Preservar a identidade encontrada e criticá-la com evidência |
| Entrega autorizada | A sessão já permite PR, merge ou deploy | Herdar a autorização concreta; senão, preparar localmente |
| Limite de frentes | Há custo ou disputa por arquivos | Seguir o [contrato de coordenação](contrato.md#4-trabalhe-em-entregas-delimitadas) |
| Critério de parada | Existe uma meta de produto clara | Definir uma entrega observável e delimitada |

Não inclua senhas, tokens ou dados pessoais em exemplos de parâmetros. A IA deve usar os mecanismos de acesso existentes, sem copiar segredos para prompts ou relatórios.

## Contextos opcionais

Para selecionar um contexto e resolver suas dependências, siga
[contextos/README.md](contextos/README.md). Esse é o contrato de seleção tanto
para o carregamento manual quanto para ferramentas que leem o manifesto.

## Carregar uma skill manualmente

Com acesso aos arquivos, peça à IA para ler a skill pelo nome (a pasta `skills/<nome>/SKILL.md`), o contrato comum e, se necessário, os contextos pertinentes. Sem acesso aos arquivos, copie o contrato comum, os parâmetros e o corpo da skill. O catálogo lista os sinais de uso de cada capacidade; o validador em `tools/` confere a integridade da biblioteca, mas não executa as instruções.

Evite combinar muitas skills em uma única solicitação. Escolha um objetivo principal. Se a investigação revelar um problema de outro tipo, a IA deve corrigir a dependência mínima indispensável ou registrar uma entrega posterior, em vez de abrir uma sequência automática de revisões.
