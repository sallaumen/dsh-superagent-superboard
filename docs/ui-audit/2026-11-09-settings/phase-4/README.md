# Settings, phase 4: Voice and summary

Baseline: phase 3 (`e64fff5`). Preview: isolated test node on port 4008
(`MIX_ENV=test MIX_TEST_PARTITION=ui_review`), a temporary fixture with a
repository, ElevenLabs configured (a saved voice "Rachel"), `voice_engine =
mixed`, `voice_input = text`, the summary on at 08:00 and the default limits.
Headless Chromium, locale `pt-BR`.

The fixture lives in `tmp/` and is not committed; it makes no provider call.

| Before (#472: one column) | After: top |
|---|---|
| [before-desktop-dark.png](before-desktop-dark.png) | [desktop-voice-dark.png](desktop-voice-dark.png) |
| [before-desktop-light.png](before-desktop-light.png) | [desktop-voice-light.png](desktop-voice-light.png) |

| After: summary, sliders and test | Phone dark | Phone light |
|---|---|---|
| [desktop-voice-bottom-dark.png](desktop-voice-bottom-dark.png) | [mobile-voice-dark.png](mobile-voice-dark.png) | [mobile-voice-light.png](mobile-voice-light.png) |
| [desktop-voice-bottom-light.png](desktop-voice-bottom-light.png) | | |

A mobile "before" capture is not available from the earlier phases; the
desktop ones are the comparison.

Observed:

- Two columns: "Você falando" on the left (input method, the stopping silence,
  "Quando o board fala", the daily summary) and "O board falando" on the right
  (engine, ElevenLabs voice + Listen, Responses, voice language, intonation,
  volume, speed, speech model, test phrase and the `.env.local` note).
- "Falar o estado agora" is in the section header, not below the controls.
- The input method is a real radio group; the two/three-value choices
  (stopping silence, engine, responses, intonation) are segmented groups with
  `aria-pressed`. The stopping silence is disabled and explained while the
  input is not the board microphone.
- The daily summary is a plain block with a switch and `type=time`, no fold;
  it still saves on change through the same action.
- On the phone the two columns become one; the four section items stay
  visible and the settings dialog sits above the board's fixed "Novo pedido"
  bar.
- All new copy is in Gettext with pt-BR; the previous leaks in this section
  ("como desejado", the uppercase engine note) are gone.
