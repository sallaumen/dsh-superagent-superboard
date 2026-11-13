# ADRs

Architecture and process decision records for this repository, in the format of
the Elixir Agent Kit [decision](https://github.com/sallaumen/elixir-agent-kit/blob/v1.0.0/priv/library/templates/decision.md) template
(local copy at `deps/elixir_agent_kit/priv/library/templates/decision.md` after `mix deps.get`).

| No. | Decision | Status |
|---|---|---|
| [0001](0001-pipelines-separados.md) | Separate pipelines by technology + mixed release path | Implemented |
| [0002](0002-ci-indisponivel.md) | CI unavailable: the local pipeline is the sufficient gate | Implemented |
| [0003](0003-ciclo-de-vida-do-agente.md) | Agent lifecycle in four edge cases: what DSH does and what the board shows | Proposed |
| [0004](0004-o-board-despacha-para-executores-locais.md) | The board dispatches to local executors: the rules of section 3.6, with D1, D2, D3 and D5 decided | Accepted |
