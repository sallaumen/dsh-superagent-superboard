# Contexto: Colmeia e gestão visual de IAs

Aplicar com `colmex-base`. O objetivo é uma cena visual de operação real, com significado verificável por trás dos elementos de jogo.

## Cena desejada

A colmeia ocupa um lado e os processos aparecem do outro como flores ou elementos equivalentes da linguagem visual. Uma flor solicita trabalho quando há demanda real. Uma abelha disponível é vinculada ao processo, vai até ele, trabalha e retorna à colmeia ao liberar sua alocação. A volta pode ter voo suave e zigue-zague, preservando fluidez e identidade.

A cena principal deve priorizar formas, movimentos e estados compreensíveis. Ao selecionar uma flor ou abelha, abra detalhes legíveis e conectados visualmente ao elemento. Não mantenha uma fila permanente de nomes técnicos, processos e botões abaixo da cena se isso consumir a área que deveria mostrar o sistema.

O usuário pediu retirar o botão de pausa desse menu visual. Investigue o que ele controla antes de removê-lo: pausa da animação, pausa de uma fila e interrupção operacional são ações diferentes. Retirar o controle desse lugar não autoriza apagar mecanismos necessários de operação. Respeite também a preferência de movimento reduzido sem depender de um botão intrusivo na cena.

## Modelo real antes da animação

Descubra como capacidade de IA, modelos, ferramentas, workers, jobs, filas e processos se relacionam. Dez abelhas é um exemplo de capacidade apresentado pelo usuário, não uma constante a fixar no código. Concorrência de jobs do Oban não equivale automaticamente a dez execuções simultâneas de IA.

Modele capacidade disponível, reservada, em execução, aguardando e desconhecida conforme os contratos reais. Diferencie alocar uma capacidade de iniciar ou terminar um job. Ao diminuir um limite, defina como o trabalho em andamento termina, sem cancelar silenciosamente operações.

O término do voo de retorno não pode controlar quando o backend libera capacidade. Se a mesma capacidade for realocada durante a animação, a cena deve reconciliar a transição sem duplicar a abelha. Animação ambiente não representa trabalho. Perda de conexão não representa disponibilidade.

## Processos sem IA

Identifique explicitamente quais tipos de worker podem usar IA, quais nunca usam e quais dependem de condição ou delegação. Escolha um contrato centralizável adequado à stack, como metadados ou comportamento, em vez de inferir pelo nome da classe ou módulo.

Esse contrato descreve capacidade potencial. Os eventos de execução dizem se houve alocação real. Um processo pai que delega a outro não pode contar a mesma IA duas vezes. Ausência de metadados deve aparecer como desconhecido até ser verificada.

Processos sem IA podem usar flores mecânicas ou artificiais, com forma e material próprios, sem parecer defeituosos ou menos importantes. Nenhuma abelha deve visitá-los sem uma alocação real. Use pistas além da cor para distinguir categoria de processo, e separe essa categoria do estado operacional de sucesso ou falha.

## Validação

Exercite ocioso, demanda, fila, alocação, execução, falha, liberação, nova alocação durante retorno e reconexão. Reconciliar o snapshot atual não deve reproduzir todos os voos antigos como trabalho novo. Meça performance com uma quantidade representativa de elementos.

Skills principais: contratos-e-dados, identidade-ui, interacoes-diretas, performance, estados-assincronos, orquestracao-ias e metricas-e-custos.
