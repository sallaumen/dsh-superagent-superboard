# Ended tickets' folders in the project's controls (2026-11-12)

Settings → Projects, a project's controls, section "Pastas de tickets
encerrados". pt-BR, light theme, taken on an isolated server (a copy of the
dev database) whose three agents pointed at fake state folders built in a
scratch directory: a git checkout, one worktree per ticket and the agent's
sqlite. No real agent's folder was read or removed for these captures.

The fake agent: five clean folders of ended tickets (three ended more than 30
days ago), one with an uncommitted file, one of an open ticket and one folder
no ticket names.

| File | What it shows |
|---|---|
| `folders-pt-light-1440.png` | what the folders hold, the retention and what passes it today |
| `folders-pt-light-390.png` | the same at 390 px, no horizontal scroll |
| `confirm-pt-light-1440.png` | the red button's sentence before anything is removed |
| `removed-pt-light-1440.png` | after "Remover tudo": the result, the panel measured again, the button gone |
