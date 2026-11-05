# Pipeline dos scripts da biblioteca

As ferramentas são determinísticas e não alteram os fontes da biblioteca (os testes criam cópias temporárias; nenhuma ferramenta executa instruções de skills, chama modelos ou acessa rede). Este documento diz **o que cada um faz**, **quando usar**, **como rodar** e **o que esperar de saída**.

## Visão geral

| Script | O que faz | Quando usar | Onde roda |
|---|---|---|---|
| [validar_biblioteca.py](validar_biblioteca.py) | Confere formato, manifesto, referências e links da biblioteca | Antes de todo commit que toque em `capabilities/`; como gate na CI | Qualquer máquina com Python 3.10+ |
| [test_validar_biblioteca.py](test_validar_biblioteca.py) | Testa o próprio validador (não o comportamento das skills) | Ao alterar o validador e junto dele nos pipelines local e CI da biblioteca | Qualquer máquina com Python 3.10+ |

## `validar_biblioteca.py`

**Entrada:** o diretório de uma biblioteca (padrão: a raiz `capabilities/` junto do script; alternativo: `--root /caminho`).

**O que confere:**

1. `manifest.json` com `schema_version` 2 e campos obrigatórios (`skills`, `contexts`, `common_contract`, `parameters`).
2. Cada `skills/<nome>/SKILL.md`: [metadados válidos](../README.md#formato-dos-metadados), localização correta, seção `## Quando usar`, instrução em `## Instrução` ou `### Instrução` e título igual ao frontmatter.
3. Manifesto × frontmatter: nenhum campo divergente.
4. `related`: toda referência resolve para uma skill existente, sem autorreferência.
5. Origem→destino: todo ID em `origin_ids` (ou derivado das skills) tem exatamente uma skill de destino; nenhuma skill usa ID não declarado.
6. Contextos: dependências resolvem, sem ciclos; caminhos existem.
7. Links locais em todos os `.md` existem e ficam dentro da biblioteca.
8. Sanidade editorial: instruções com densidade fora da faixa geram aviso; corpos duplicados geram erro.

**Saída:** linha `OK` ou `FALHOU` com a lista de erros e avisos; `--json` emite relatório estruturado (`ok`, `skills`, `contexts`, `origins`, `body_words`, `local_links_checked`, `errors`, `warnings`, `skill_stats`).

| Código de saída | Significado |
|---|---|
| `0` | Validação concluída sem erros; pode haver avisos editoriais |
| `1` | Validação concluída com erros no relatório |
| `2` | Argumentos inválidos ou falha que impede produzir o relatório, como manifesto ilegível ou incompatível; diagnóstico em stderr |

**Como rodar, a partir da raiz do repositório:**

```bash
python3 capabilities/tools/validar_biblioteca.py
python3 capabilities/tools/validar_biblioteca.py --json
python3 capabilities/tools/validar_biblioteca.py --root /caminho/da/biblioteca
```

## `test_validar_biblioteca.py`

**Entrada:** nenhuma. Copia a biblioteca (e bibliotecas mínimas sintéticas) para diretórios temporários e aplica mutações controladas.

**O que confere:** o validador detecta cada classe de defeito — manifesto divergente, frontmatter incompleto, `related` inexistente/autoreferente, cobertura de origem incompleta/duplicada/não declarada, skill duplicada, ciclo e dependência desconhecida de contextos, link local quebrado, caminho fora da biblioteca, corpos duplicados, modo inválido e instrução ausente — além de aceitar uma biblioteca válida e uma biblioteca estrangeira com IDs próprios.

Os testes protegem a ferramenta; a avaliação comportamental das skills é descrita em [casos-de-avaliacao.md](../validacao/casos-de-avaliacao.md).

**Como rodar, a partir da raiz do repositório:**

```bash
python3 capabilities/tools/test_validar_biblioteca.py
```

## Adotar os scripts em outro projeto

A ferramenta é genérica por construção:

1. Copie `tools/validar_biblioteca.py` para `tools/` na raiz da biblioteca de destino (opcionalmente `test_validar_biblioteca.py` com o helper de biblioteca mínima adaptado).
2. Adote o layout: `manifest.json` schema 2 + `skills/<nome>/SKILL.md` com os [metadados documentados](../README.md#formato-dos-metadados), `contrato.md` e `parametros.md` (ou aponte os campos para os arquivos equivalentes do projeto).
3. Declare `origin_ids` com os identificadores da sua origem (qualquer string não vazia) ou omita para derivar das skills.
4. Rode `python3 tools/validar_biblioteca.py --root .` na raiz da biblioteca de destino e adicione o mesmo comando ao seu pipeline de CI.

Sem dependências externas: somente Python 3.10+ com biblioteca padrão.
