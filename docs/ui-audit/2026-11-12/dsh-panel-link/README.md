# The dsh panel, signed in, from the project's controls (2026-11-12)

Settings → Projects, a project's controls, the "Painel dsh" fold. pt-BR,
light theme, taken on an isolated server (a copy of the dev database) whose
agents pointed at fake orchestrators and whose `DSH_SUPERAGENT_HOME` was a
scratch folder with one invented log line. No real agent's log was read and
no real launch token was used.

| File | What it shows |
|---|---|
| `button-pt-light-1440.png` | the button, and the script kept as the fallback |
| `button-pt-light-390.png` | the same at 390 px: no horizontal scroll, a 44 px button |
| `no-log-pt-light-1440.png` | an agent with no log: the new tab opens Projects with the reason |

Clicking the button for the agent that had a log opened a new tab at that
agent's own address (`http://127.0.0.1:4732/?token=…`, the invented value),
which is the whole success path: there is no board screen to capture.

The "Pastas de tickets encerrados" section above the fold says it could not
measure the folders because the copy's agents had no state folder; that is
the capture setup, not this change.
