# Adding an agent installed outside the board (2026-11-12)

Settings → Projects. pt-BR, light theme, taken on an isolated server (a copy
of the dev database) whose profiles folder was a scratch directory with one
invented profile, `superagent-site`, answered by a fake orchestrator that
named `example-org/site` as its repository. No real profile or agent was
read, started or changed.

| File | What it shows |
|---|---|
| `installed-pt-light-1440.png` | the agent the board does not follow, above "Adicionar projeto" |
| `installed-pt-light-390.png` | the same at 390 px, no horizontal scroll |
| `confirm-pt-light-1440.png` | the sentence before anything is registered |
| `added-pt-light-1440.png` | after the click: the result, the new project row, the list gone |

The new row says "Sem leitura" because the capture server's ticker was off;
on a running board the next tick reads the agent.
