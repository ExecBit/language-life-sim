# Issue #62 verification

Run with Godot 4.7.1 console executable from the project root. In this environment the restricted sandbox crashes the engine before startup; the authorized runs outside that sandbox complete.

| Check | Result | Evidence |
| --- | --- | --- |
| Parser/resolver and scene regression | PASS | `--headless --path . --script res://implementations/communication_lab/tests/test_lab.gd --quit-after 120`: 36 PASS lines, zero assertion failures. Scene resource is loaded after autoload initialization. |
| Actual rendered normal/debug UI | PASS | `--path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/capture_ui.gd --quit-after 180`. Inspected actual viewport captures of normal conversation and all four debug tabs. Iterated after finding bottom clipping; final panel bounds assertion passes. |
| Composer/history/reset workflow | PASS | Same capture runner submits via composer, including an unconfirmed prefix token; verifies history recall does not restore world state, reset preserves attempts, and closing restores movement and hides tools. |
| Isolation / F5 entry | PASS | No cross-variant resource dependencies added; project.godot remains unchanged. Parser/catalog/resolver semantics unchanged. |
| Shared Cogito audio initialization | FAIL | CLI test launches report existing `Audio._play_sound` null stream and `CogitoPlayerSimple.slide_audio_init` reparent errors, plus resource cleanup warnings. Lab UI/scene assertions still complete. Shared addons are outside this UI change. |
| Real mouse/keyboard exploratory session | NOT_TESTED | Verification used rendered engine frames and automated UI method calls, not human input. |
| Exported build / audio | NOT_TESTED | No candidate export or audio behavior validated in this follow-up. |

Screenshots and raw logs are in ignored `.local/`. Captures reflect the actual imported local Astera model; the closed model remains uncommitted and clean checkouts use Anna fallback.

## Reproduction

1. F6 the lab scene, approach Astera and press E. Enter `Hallo`; Enter sends. Use catalog search + Tab to append a word. Unknown words remain accepted as input.
2. F2 opens the laboratory. Set NPC busy and repeat `Hallo`; compare the response in History. Select either attempt, then inspect Parse / Response and effects / State.
3. Reset context, submit `Ich brauche den Schlüssel`, then submit again: only the first transfer changes ownership. Inspect live controls and before/after state.
4. Recall an earlier attempt, edit and explicitly submit it under current context. Reset preserves this history while clearing pending conversation state.
5. Test `Ja` / `Nein` inside and outside pending offer, `Schlüssel?`, `Wo ist der Schlüssel?`, `Öffne die Tür nicht.`, and `Ich will Flöte.`. Inspect unsupported/unknown results without world effects.
6. Hide tools with F2; close conversation with Esc and continue moving.

The parser keeps its original internal Anna vocabulary/addressee; the visible avatar is Astera. Recognition does not imply unrestricted German comprehension.
