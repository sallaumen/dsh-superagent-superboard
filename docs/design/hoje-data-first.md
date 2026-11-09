# Hoje: dados e funções antes do refinamento visual

## Propósito

Hoje é a entrada para todos os projetos acompanhados. A ordem de leitura é: resultados do dia, decisões que pedem o dono, trabalho em andamento, distribuição por projeto, tendência de PRs, uso e o último resumo gerado pelo board.

## Significado dos dados

| Elemento | Fonte e período | Limite a preservar |
|---|---|---|
| PRs mesclados hoje | PRs salvos no board com `merged_at` no dia local do navegador | Pode faltar histórico que nunca foi sincronizado. Não chamar de total do GitHub. |
| Issues vistas hoje | Tarefas do tipo issue cujo registro foi criado no board no dia local | Primeira leitura pelo board; não é a abertura da issue no GitHub. |
| Na fila agora | Tarefas ativas em `queued`, excluindo execução local que já começou | É estado atual, não volume produzido hoje. |
| Precisa de você / Rodando agora | Leitura ativa de tarefas de todos os projetos e execuções locais | Não incluir tarefas paradas, arquivadas ou revisão já resolvida por PR mesclado. |
| Por projeto | Contagem dos estados acima, PRs mesclados hoje e última sincronização | Leitura atrasada, falha ou ausente deve permanecer visível; número salvo não equivale a estado atual do GitHub. |
| PRs mesclados · 7 dias | Mesmo `merged_at`, agrupado pelos sete dias locais terminando hoje | Dias sem registro valem zero **no board**. |
| Uso hoje | Livro de uso por fonte e cota semanal do Codex | Dólares estimados e porcentagem de cota são unidades distintas. |
| Resumo do dia do board | Registro persistido, com janela desde o resumo anterior | Não substituir sua janela por “desde meia-noite” nem recalcular os fatos salvos. |

## Estados e interação

- O nome do projeto abre seu board. As listas de trabalho abrem a tarefa no projeto correto.
- Sem projetos: mostrar estado vazio do quadro por projeto; o gráfico pode manter sete dias zerados, com o escopo “registrados no board”.
- Sincronização ausente, atrasada ou falha: rotular a leitura em vez de esconder o projeto.
- O resumo persistido só aparece quando ainda está visível. Dispensar segue ocultando em todas as abas.
- Dados recebidos por broadcast atualizam sem animação; mudança de estado não deve depender de movimento.

## Próximo passe visual

Refinar ritmo, tipografia e densidade dos blocos após validar o conteúdo com uso real. O gráfico pode ganhar melhor escala e comparação, desde que continue legível por texto e preserve a origem dos dados. A tabela por projeto deve conservar suas colunas e navegação, inclusive em tela estreita. Seguir [DESIGN.md](redesign/DESIGN.md), os padrões do board e [ui-motion.md](../ui-motion.md).
