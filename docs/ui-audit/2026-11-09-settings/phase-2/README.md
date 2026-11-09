# Settings, phase 2: Projects as one list

Baseline: phase 1 (`4ddb13d`). Preview: isolated test node on port 4008
(`MIX_ENV=test MIX_TEST_PARTITION=ui_review`), a temporary fixture seeded with
two projects: `ui-fixture/read-only` (ready, 3 agents, owner + one allowed
person, two waiting logins) and `ui-fixture/broken-source` (error, source does
not point to a repository). Headless Chromium, locale `pt-BR`.

The fixture used `scripts/ui_review_fixture.exs` as the base plus a local
preview script in `tmp/` that is not committed; it stubs the manager and the
GitHub collaborators, and it seeds the refused mentions in the agent's SQLite
state. No real project or GitHub repository was read or changed.

| Capture | Viewport | Theme |
|---|---|---|
| [desktop-projects-list-dark.png](desktop-projects-list-dark.png) | 1280×900 | dark |
| [desktop-projects-list-light.png](desktop-projects-list-light.png) | 1280×900 | light |
| [desktop-projects-expanded-dark.png](desktop-projects-expanded-dark.png) | 1280×900 | dark |
| [desktop-projects-expanded-light.png](desktop-projects-expanded-light.png) | 1280×900 | light |
| [desktop-projects-add-dark.png](desktop-projects-add-dark.png) | 1280×900 | dark |
| [desktop-projects-add-light.png](desktop-projects-add-light.png) | 1280×900 | light |
| [mobile-projects-dark.png](mobile-projects-dark.png) | 390×844 | dark |
| [mobile-projects-light.png](mobile-projects-light.png) | 390×844 | light |

Before this phase, the same section was the old repository form plus the
superagents table and the separate access section:
[desktop dark](../phase-1/desktop-projects-dark.png) ·
[desktop light](../phase-1/desktop-projects-light.png) ·
[mobile dark](../phase-1/mobile-projects-dark.png) ·
[mobile light](../phase-1/mobile-projects-light.png).

Observed:

- One list, never a horizontally scrolling table. `owner/` is faint, the
  project name is bold, and the state is a glyph plus a word (`● Ligado`,
  `■ Não sobe`).
- The waiting mark uses the `you` diamond; the error mark uses the halt square.
  The nav shows both counts (`■ 1 ◆ 2`) without relying on color alone.
- Expanding a row (`aria-expanded`) shows the waiting requests on the left and
  "Quem pode chamar o agente" plus "Adicionar pessoa" on the right. The owner
  has no Revogar; the other person does. The server error is a halt-wash strip
  under its own row, with "Detalhes técnicos" as the action.
- The single add form has Owner, Repository, Local folder, the checked
  "Criar um agente DeepSeek para ele" and the initial-agents stepper. Unchecked
  it is the old "track only" path; checked it asks for the confirmation before
  provisioning.
- On the phone the row stacks, the four section items stay visible, and the
  settings dialog sits above the board's fixed "Novo pedido" bar.

The collaborators read is covered by a test that collapses and reopens the
row and asserts the GitHub read still happens once; the access read itself
comes from `BoardLive`'s existing `agent_access_projects`.
