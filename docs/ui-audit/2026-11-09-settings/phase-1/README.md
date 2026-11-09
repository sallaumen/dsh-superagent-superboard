# Settings, phase 1: four sections, old URLs and the version footer

Baseline: `main` at `07fe3f5`. Preview: isolated test node on port 4008
(`MIX_ENV=test MIX_TEST_PARTITION=ui_review`), fixture
`scripts/ui_review_fixture.exs`, repository `ui-fixture/read-only`, locale
`pt-BR`, headless Chromium.

The phase only regroups the content that already existed; Projects still
shows the old repository forms and the old superagents table. The new parts
are the four-item navigation, the URL aliases and the version footer.

Before, the same fixture on `07fe3f5` (the ten-section menu):

| Before | Viewport | Theme |
|---|---|---|
| [before-desktop-dark.png](before-desktop-dark.png) | 1280×900 | dark |
| [before-desktop-light.png](before-desktop-light.png) | 1280×900 | light |
| [before-mobile-dark.png](before-mobile-dark.png) | 390×844 | dark |
| [before-mobile-light.png](before-mobile-light.png) | 390×844 | light |

After, the four-section menu:

| After | Viewport | Theme |
|---|---|---|
| [desktop-projects-dark.png](desktop-projects-dark.png) | 1280×900 | dark |
| [desktop-projects-light.png](desktop-projects-light.png) | 1280×900 | light |
| [mobile-projects-dark.png](mobile-projects-dark.png) | 390×844 | dark |
| [mobile-projects-light.png](mobile-projects-light.png) | 390×844 | light |

Observed:

- Four items: Projetos, Execução, Voz e resumo, Sistema. The active item
  carries `aria-current="page"`.
- The footer shows the running short sha, the comparison with `main` and
  "Ver atualização", which opens Sistema.
- On the phone the items scroll horizontally and the version footer sits
  below them, above the content.
- Old URLs (`section=repositories|superagents|access|dispatch|inspect|summary|appearance|language|version`)
  open the new section; the LiveView tests cover each key.

The preview had no Claude/Codex usage and no superagents, so the quota and
the project marks are not visible in this set. The project-error mark is
covered by `AgentBoardWeb.SettingsSectionTest`; the waiting-for-access mark
is covered by the access tests.
