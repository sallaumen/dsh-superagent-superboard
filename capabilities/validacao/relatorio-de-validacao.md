# Relatório de validação da biblioteca de capacidades

**Edição:** 2.0.0 (incorporação da biblioteca-prompts-desenvolvimento v1.0.0 ao repositório agent-board).
**Data:** 4 de novembro de 2026.

## 1. Validação de formato e integridade

- `python3 capabilities/tools/validar_biblioteca.py` — **OK**: 32 skills; 6 contextos; 21.838 palavras nas instruções; 196 links locais conferidos; 0 erros, 0 avisos. Cobertura completa e sem duplicação dos IDs de origem P01–P34.
- `python3 capabilities/tools/test_validar_biblioteca.py` — **16 testes, todos aprovados** (biblioteca válida; divergência manifesto×frontmatter; frontmatter incompleto; `related` inexistente ou autorreferente; cobertura de origem incompleta; destino duplicado; skill duplicada; ciclo de contextos; dependência de contexto inexistente; link local quebrado; caminho que escapa da biblioteca; corpos duplicados; modo inválido; relatório JSON; ausência de instrução).
- Conferências cobertas: frontmatter × manifesto; localização `skills/<nome>/SKILL.md`; resolução de `related`; dependências e ciclos de contextos; links locais em todos os `.md`; caminhos restritos à biblioteca; densidade editorial.

## 2. Revisão editorial

- Todos os 34 prompts-fonte, os 6 contextos, as referências e os templates foram lidos integralmente durante a incorporação.
- Adaptações aplicadas: referências cruzadas renomeadas para nomes de skills; menções a "prompt" ajustadas onde descreviam a própria capacidade; seções do compositor removidas; manifestos e catálogos reescritos; seção final dos roteiros corrigida (a substituição da seção "Transformação desta biblioteca em skills" foi detectada na revisão pós-geração e corrigida).
- Não foram encontradas contradições materiais entre prompts; a fusão P12+P13 removeu a duplicação de técnica de evidência e P01+P02 centralizou a mecânica de coordenação.
- A revisão estática independente citada pela edição de origem cobria P01–P14 e P34; esta edição releu o conjunto completo.

## 3. Resultados das verificações executadas

| Verificação | Comando | Resultado |
|---|---|---|
| Validador da biblioteca | `python3 capabilities/tools/validar_biblioteca.py` | OK (0 erros, 0 avisos) |
| Testes do validador | `python3 capabilities/tools/test_validar_biblioteca.py` | 16/16 aprovados |
| Gates do repositório Elixir | `mix precommit` (format + credo strict + test) | OK; 41 testes, 0 falhas |

## 4. Execução de cenários controlados

Executores independentes (contexto separado, sem acesso aos critérios esperados) avaliaram a biblioteca já transformada.

### Roteamento (27 pedidos)

O executor recebeu apenas o catálogo e as skills, e escolheu: E01 `coordenar-entregas`; E02 `revisar-arquitetura`; E03 `stratified-design`; E04 `identidade-ui`; E05 `espaco-e-densidade`; E06 `mobile-e-responsividade`; E07 `performance`; E08 `notificacoes-e-bots`; E09 `orquestracao-ias`; E10 `elegibilidade-comercial`; E11 `testes-redundantes`; E12 `code-review`; E13 `coordenar-entregas`; E14 `simulacao-e-producao`; E15 `metricas-e-custos`; E16 `incorporacao`; E17 `versoes-e-rastreabilidade`; E18 `NONE` (pedido pequeno); E19 `alertas-operacionais`; E20 `migracoes-e-compatibilidade`; E21 `estrategia-de-testes`; E22 `build-ci-dependencias`; E23 `validar-entrega`; E24 `seguranca-e-permissoes`; E25 `identidade-ui`; E26 `coordenar-entregas`; E27 `coordenar-entregas`.

Resultado: **27/27 dentro do esperado ou de alternativa admitida**. E27 foi roteado para `coordenar-entregas` em vez de `code-review`; como o critério do caso é o limite de autorização (verificado separadamente), `coordenar-entregas` foi registrada como alternativa admitida em [casos-de-avaliacao.json](casos-de-avaliacao.json).

### Code review somente leitura (fixture)

O executor recebeu `skills/code-review`, o contrato e a fixture em [fixtures/code-review/](fixtures/code-review/) (a mudança retira o filtro de variante ao selecionar fornecedores elegíveis), sem o diagnóstico esperado. Resultado:

- Identificou a regressão (remoção de `item["variant_id"] == variant_id`), com gravidade, localização, condição, consequência e evidência de execução (`before → ['S1']`, `after → ['S1', 'S2']`).
- Separou hipóteses (intenção do autor; padrões preexistentes) de achado confirmado.
- **Hashe sha256 dos três arquivos idênticos antes e depois**: nenhuma alteração aplicada, conforme o modo somente leitura.
- Concluiu "PRECISA DE CORREÇÃO" sem aprovar, mergear ou publicar.

### Cenários de limite (4 pedidos)

Outro executor independente respondeu:

1. **UI sem contexto de jogo** (site de aulas de música): `identidade-ui`, **nenhum contexto carregado**, sem estética de jogo do Colmex.
2. **Fornecedor com variante desconhecida**: `elegibilidade-comercial`; variante sem confirmação permanece pendente/desconhecida e bloqueada — sem deduzir disponibilidade a partir da camiseta preta.
3. **Ambiente sem delegação/listener**: `coordenar-entregas` com execução sequencial explícita, sem simular paralelismo.
4. **Ação externa sem autorização**: recusa de merge e publicação; entrega revisável pronta e indicação da autorização específica que falta (`validar-entrega` como capacidade de continuação).

Os quatro cenários atenderam aos sinais esperados.

## 5. Uso em projeto real

Não realizado nesta edição: nenhum workflow foi executado contra os produtos (Colmex, forró) e nenhuma skill foi instalada em um agente específico. O repositório agent-board recebeu apenas a biblioteca e ponteiros em AGENTS.md/README.md; os gates do projeto Elixir foram executados para comprovar ausência de regressão.

## 6. Limites

- Validação comportamental restrita a cenários sintéticos e fixtures; não mede desempenho das capacidades em produção.
- Instalação/compatibilidade com plataformas de agentes não verificada; o formato segue a especificação documentada de Agent Skills (pasta SKILL.md com frontmatter `name`/`description`).
- Contextos de projetos específicos permanecem intenções relatadas, não inventários verificados.
