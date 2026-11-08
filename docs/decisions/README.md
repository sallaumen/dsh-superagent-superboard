# ADRs

Registros de decisão arquitetural e de processo deste repositório, no formato
do template [decision](https://github.com/sallaumen/elixir-agent-kit/blob/v0.8.0/priv/library/templates/decision.md) do Elixir Agent Kit
(cópia local em `deps/elixir_agent_kit/priv/library/templates/decision.md` após `mix deps.get`).

| Nº | Decisão | Estado |
|---|---|---|
| [0001](0001-pipelines-separados.md) | Pipelines separados por tecnologia + caminho misto de release | Implementada |
| [0002](0002-ci-indisponivel.md) | CI indisponível: pipeline local é o gate suficiente | Implementada |
| [0003](0003-ciclo-de-vida-do-agente.md) | Ciclo de vida do agente em quatro situações de borda: o que o DSH faz e o que o board mostra | Proposta |
| [0004](0004-o-board-despacha-para-executores-locais.md) | O board despacha para executores locais: as regras da seção 3.6, com D1, D2, D3 e D5 decididas | Aceita |
