# Board identity, Chat and Settings

The same three queued fixture tickets were used for both versions. Baseline:
`9793d8c`. The browser was headless WebKit, in Brazilian Portuguese, at
1440 × 1000 and 375 × 812. The fixtures used an isolated test database,
simulated setup checks and a local log sample; no real AI responses were requested.

| Surface | Before | After |
| --- | --- | --- |
| Board and navigation | [Desktop](before-brand.png) | [Desktop](after-brand.png) · [Dark](after-brand-dark.png) · [Mobile, dark](after-brand-mobile.png) |
| Chat | [Desktop](before-chat.png) · [Mobile](before-chat-mobile.png) | [Desktop](after-chat.png) · [Mobile](after-chat-mobile.png) · [Skill response](after-chat-response.png) |
| AI and setup | [Setup](before-setup.png) | [Reopened after a successful check](after-setup.png) |
| Logs | [Standalone panel](before-logs.png) | [Inside Settings](after-logs.png) |

- Both “Super” labels start at the same horizontal position. The two favicon
  formats loaded; the mobile page fit the viewport without horizontal scrolling.
- Double Space on the board opened Chat with focus in the message field.
  A Status card sent its question and displayed the saved board counts.
- After checking setup, closing Settings, returning and reloading the page,
  the receipt still had precisely the original timestamp.
- Pausing Logs and clicking Refresh kept the monitor paused. A severity filter
  survived a reload. The old Logs URL also opened the Settings section.
