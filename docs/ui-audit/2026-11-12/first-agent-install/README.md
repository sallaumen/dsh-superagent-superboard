# Installing a machine's first agent from "Adicionar projeto" (2026-11-12)

Settings → Projects, "Adicionar projeto". pt-BR, light theme, taken on an
isolated server whose copy of the dev database had its agents removed (the
copy only), with an empty profiles folder and a scratch folder for the bot's
sign-in. The install was **not confirmed**: every capture stops at the
sentence, and "Agora não" was pressed. Nothing was installed for a capture.

| File | What it shows |
|---|---|
| `blocked-pt-light-1440.png` | no sign-in for the agent: the form says what is missing and asks nothing |
| `sentence-pt-light-1440.png` | the sentence of the install, with "Instalar o agente" |
| `sentence-pt-light-390.png` | the same at 390 px, no horizontal scroll |

What the confirmed click does was exercised apart from the screen: in tests,
with a fake `dsh` and a fake agent, and by hand against the real `dsh` in a
scratch `DSH_HOME` (the contract's "A machine's first agent" says which
steps ran for real and which did not).
