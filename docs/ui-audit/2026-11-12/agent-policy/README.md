# Projects: the agent's instructions against the board's policy (2026-11-12)

Captured in headless WebKit from an isolated server: a copy of the dev
database with the three agents' ports pointed at fake orchestrators that
serve and accept `/prompts`. No real agent was read or written. One fake held
the policy; two held an older rule and a rule of their own.

| File | What it shows |
|---|---|
| `bell-pt-light-1440.png` | Attention: the agents whose instructions differ, first in the list |
| `different-pt-light-1440.png` | a project's controls: what differs per section, each agent-only rule with its checkbox |
| `different-bottom-pt-light-1440.png` | the rest of the list and the button |
| `applied-pt-light-1440.png` | after the click with one rule kept: up to date, and the rule listed as the project's |
| `applied-pt-light-390.png` | the same on a phone |

After the click the fake held the policy plus the kept rule at revision 4,
its other keys unchanged; the other agent stayed at revision 3.
