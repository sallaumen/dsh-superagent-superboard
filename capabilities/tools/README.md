# Pipeline dos scripts da biblioteca

Esta biblioteca tem dois scripts executáveis, ambos determinísticos e somente leitura (não executam instruções de skills, não chamam modelos, não acessam rede). Este documento diz **o que cada um faz**, **quando usar**, **como rodar** e **o que esperar de saída**.

## Visão geral

| Script | O que faz | Quando usar | Onde roda |
|---|---|---|---|
| `validar_biblioteca.py` | Confere formato, manifesto, referências e links da biblioteca | Antes de todo commit que toque em `capabilities/`; como gate na CI | Qualquer máquina com Python 3.10+ |
| `test_validar_biblioteca.py` | Testa o próprio validador (não as skills) | Após alterar o validador; para comprovar que a ferramenta continua detectando erros | Qualquer máquina com Python 3.10+ |

## `validar_biblioteca.py`

**Entrada:** o diretório de uma biblioteca (padrão: a raiz `capabilities/` junto do script; alternativo: `--root /caminho`).

**O que confere (nessa ordem):**

1. `manifest.json` com `schema_version` 2 e campos obrigatórios (`skills`, `contexts`, `common_contract`, `parameters`).
2. Cada `skills/<nome>/SKILL.md`: frontmatter completo (`name`, `title`, `category`, `default_mode`, `origem`, `related`, `description`), localização correta, seções `## Quando usar` e `## Instrução`, título igual ao frontmatter.
3. Manifesto × frontmatter: nenhum campo divergente.
4. `related`: toda referência resolve para uma skill existente, sem autorreferência.
5. Origem→destino: todo ID em `origin_ids` (ou derivado das skills) tem exatamente uma skill de destino; nenhuma skill usa ID não declarado.
6. Contextos: dependências resolvem, sem ciclos; caminhos existem.
7. Links locais em todos os `.md` existem e ficam dentro da biblioteca.
8. Sanidade editorial: instruções com densidade fora da faixa geram aviso; corpos duplicados geram erro.

**Saída:** linha `OK` ou `FALHOU` com a lista de erros e avisos; `--json` emite relatório estruturado (`ok`, `skills`, `contexts`, `origins`, `body_words`, `local_links_checked`, `errors`, `warnings`). Código de saída 0/1 — seguro para gates de CI.

**Quando usar:**

- **Local:** antes de commitar qualquer mudança em skills, catálogo, contextos ou manifesto.
- **CI:** como job da biblioteca em todo PR (veja o pipeline do repositório).

**Como rodar:**

```bash
python3 capabilities/tools/validar_biblioteca.py
python3 capabilities/tools/validar_biblioteca.py --json
python3 capabilities/tools/validar_biblioteca.py --root /caminho/da/biblioteca
```

## `test_validar_biblioteca.py`

**Entrada:** nenhuma. Copia a biblioteca (e bibliotecas mínimas sintéticas) para diretórios temporários e aplica mutações controladas.

**O que confere:** o validador detecta cada classe de defeito — manifesto divergente, frontmatter incompleto, `related` inexistente/autoreferente, cobertura de origem incompleta/duplicada/não declarada, skill duplicada, ciclo e dependência desconhecida de contextos, link local quebrado, caminho fora da biblioteca, corpos duplicados, modo inválido e instrução ausente — além de aceitar uma biblioteca válida e uma biblioteca estrangeira com IDs próprios.

**Quando usar:** sempre que `validar_biblioteca.py` mudar; nunca como gate das skills (não as avalia).

**Como rodar:**

```bash
python3 capabilities/tools/test_validar_biblioteca.py
```

## Adotar os scripts em outro projeto

A ferramenta é genérica por construção:

1. Copie `tools/validar_biblioteca.py` para o projeto (opcionalmente `test_validar_biblioteca.py` com o helper de biblioteca mínima adaptado).
2. Adote o layout: `manifest.json` schema 2 + `skills/<nome>/SKILL.md` com o frontmatter da seção de formato, `contrato.md` e `parametros.md` (ou aponte os campos para os arquivos equivalentes do projeto).
3. Declare `origin_ids` com os identificadores da sua origem (qualquer string não vazia) ou omita para derivar das skills.
4. Rode `python3 validar_biblioteca.py --root .` no diretório do projeto e adicione o mesmo comando ao seu pipeline de CI.

Sem dependências externas: somente Python 3.10+ com biblioteca padrão.
