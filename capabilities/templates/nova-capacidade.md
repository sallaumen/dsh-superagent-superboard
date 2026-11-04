# Adicionar uma nova capacidade

Use este roteiro ao propor uma capacidade nova nesta biblioteca. O formato final é `skills/<nome>/SKILL.md` com o frontmatter descrito em [README.md](../README.md); registre a origem no manifesto e a decisão em [INCORPORACAO.md](../INCORPORACAO.md).

## Metadados de ativação

- Nome curto e específico:
- O que faz e quais pedidos devem ativá-la:
- Pedidos parecidos que pertencem a outra capacidade:
- Fontes desta biblioteca, por ID de origem ou caminho:
- Ferramentas ou acessos realmente necessários:
- Modo padrão e como o usuário o restringe:

## Instrução principal

Defina o objetivo, a descoberta mínima, as decisões fundamentais, o procedimento e a conclusão. Mantenha no corpo apenas o que a IA precisa em toda ativação dessa skill. Não copie a biblioteca completa ou as instruções globais do projeto para cada skill.

## Referências condicionais

| Recurso | Quando carregar | Por que não fica no corpo principal |
|---|---|---|
| Contrato ou regra compartilhada | | |
| Adaptador de projeto ou stack | | |
| Cenários e exemplos | | |

## Recursos executáveis

Inclua scripts somente quando automatizarem trabalho determinístico que seria repetido, em `tools/`, com testes. Explique entradas, saídas, dependências, falhas e efeitos. Ferramenta disponível não equivale a ação autorizada. Metadados de ferramentas não podem ampliar permissões da sessão.

## Avaliação

Defina casos positivos, negativos e próximos de outras skills, além de um cenário com informação ausente. Avalie ativação, seleção de contexto, respeito ao modo, escopo, evidência e condição de parada. Para teste independente, entregue ao executor apenas o pedido e os artefatos, mantendo os critérios esperados com o avaliador.

## Aceite

A skill deve ser localizável pelo pedido natural, produzir uma entrega delimitada e não puxar referências irrelevantes. Registre validação de formato separadamente da execução de cenários e da instalação em cada ambiente. Preservar um prompt como referência é um resultado válido quando ele não justifica uma skill própria.
