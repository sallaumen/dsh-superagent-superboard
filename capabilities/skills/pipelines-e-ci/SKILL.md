---
name: "pipelines-e-ci"
title: "Pipelines de projeto: separação por tecnologia e paridade local×CI"
category: "qualidade"
default_mode: "analisar-e-corrigir"
origem: ["B01"]
related: ["build-ci-dependencias", "validar-entrega"]
description: "Use quando um projeto precisa organizar ou auditar seus pipelines de validação: separar backend, frontend e ferramentas auxiliares com o melhor padrão para cada um, manter paridade entre comandos locais e CI e decidir quando um pipeline misto de release é necessário. Para consertar um pipeline quebrado (CI oscilando, build não reproduzível), use build-ci-dependencias."
---

# Pipelines de projeto: separação por tecnologia e paridade local×CI

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando um projeto precisa organizar ou auditar seus pipelines de validação: como e quando usar cada script, separar backend, frontend e ferramentas auxiliares com o melhor padrão para cada um, decidir quando um pipeline misto é necessário e o que fazer quando um gate remoto fica indisponível. Para consertar um pipeline quebrado — CI oscilando, build não reproduzível, dependências com manutenção pendente — use `build-ci-dependencias`.

## Entradas úteis

- Scripts, aliases e alvos de build já existentes (mix, make, npm, Python…) e o workflow de CI atual.
- Stack de cada lado: backend, frontend e ferramentas auxiliares, incluindo onde cada toolchain está disponível (ex.: esbuild/tailwind como dependências de dev).
- Bloqueios conhecidos da conta ou da CI: sem token, sem runner, pendência de cobrança.

## Instrução

Audite e organize os pipelines de validação do projeto em camadas coerentes. O objetivo é que qualquer pessoa ou IA saiba qual script rodar em cada situação, que o local e a CI executem os mesmos comandos e que nenhum lado fique sem gate.

### Inventarie o que já existe

Liste scripts, aliases, alvos de make/just e jobs de CI. Para cada um, registre o que valida, quando deve ser usado, o ambiente necessário, os efeitos e a saída esperada. Marque divergências: CI executando menos que o local, comandos sem documentação, gates prometidos que não existem, artefatos de build sujando o working tree.

### Separe por tecnologia

Agrupe por pipeline: backend (compilação com warnings como erro, formato, lint, testes — com partições quando a suíte justificar), frontend (build de assets no ambiente onde as ferramentas existem), bibliotecas e ferramentas auxiliares (validador próprio, somente leitura) e, quando o deploy exigir, um pipeline misto de release que exercite o caminho combinado dos dois lados. Cada pipeline precisa de uma entrada local equivalente ao job da CI — idealmente o mesmo comando, para que local e CI nunca divirjam. Prefira jobs com nomes que digam qual lado quebrou.

### Torne o uso explícito

Documente a matriz de scripts (quando usar, ambiente, efeitos, saída) em um único lugar, aponte as instruções do projeto para ela e adicione um teste de contrato que falhe quando aliases ou workflow divergirem da documentação. Um script sem linha na matriz não tem "quando usar" definido. Mantenha um pré-voo único (ex.: `make check` ou um script) que rode os pipelines separados na ordem da CI.

### Defina o comportamento sem gate remoto

Registre a regra: se a CI não consegue rodar por bloqueio fora do repositório (sem token, sem runner, pendência de cobrança), não espere por ela nem trave entregas — execute o pipeline local com evidência, siga quando estiver verde e registre a limitação e o comando executado; re-verifique o gate remoto quando o bloqueio for resolvido. A indisponibilidade nunca dispensa os checks locais, e re-disparar runs sem resolver o bloqueio só consome cota.

### Valide e conclua

Rode cada pipeline novo e o caminho misto, corrija até ficar verde e confira que o working tree não acumula artefatos. Entregue a matriz de scripts, as decisões com alternativas consideradas, os comandos executados e as limitações. Conclua quando qualquer mudança de qualquer lado tiver um gate claro, com local e CI sem divergência, e quando a indisponibilidade do gate remoto tiver um comportamento definido.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Modelo de registro: [templates/registro-de-decisao.md](../../templates/registro-de-decisao.md)
