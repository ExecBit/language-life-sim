# Issue #62 verification

Run from the project root with Godot 4.7.1 console executable. In this environment, the restricted sandbox blocks Godot's profile/cache writes; the successful CLI runs were approved outside the sandbox. Logs and screenshots remain under ignored `.local/`.

| Check | Result | Evidence |
| --- | --- | --- |
| Headless editor import | PASS | `Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --quit`, exit code 0. Godot reports editor ObjectDB/resource cleanup warnings at exit. |
| Parser, resolver, and scene regression | PASS | `--headless --path . --script res://implementations/communication_lab/tests/test_lab.gd`, exit code 0; 56 `PASS` assertions, 0 assertion failures. Covers original parser/context regression cases, nonlinear dialogue intents, name/mood/plan context, help/slow speech, unknown safety, VRM joy morph, spawn interaction range, synthetic E-key open, generated motions and return to idle. |
| Actual rendered player/debug/memo UI | PASS | `--path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/capture_ui.gd`; `UI_WORKFLOW: PASS`. The script renders and saves the opening greeting, happy face, cup-pointing reply, word memo, all debug tabs and the conversation after testing. Those images were inspected. |
| Gesture and prop staging | PASS | Rendered `Was machst du?` frame shows Astera looking/gesturing down at the table; the cup is visible on the tabletop. The motion returns to idle in the runtime test. This verifies visual direction and scene staging, not hand-to-cup contact or phrase-level timing. |
| VRM expression mapping | PASS | Both local avatar VRMs expose the same VRM0 preset bindings: neutral 0, angry 1, fun 2, joy 3, sorrow 4, surprised 5; vowels A–O 39–43; blink variants 13–15. Godot imports the active facial mesh as `morph_0..56`; the test verifies the happy blend drives `morph_3`. Screenshots show the rendered facial change. Blink and vowel channels are available but not animated. |
| Isolation and default entry | PASS | No `project.godot` or other implementation files were changed. Communication Lab runtime resource paths remain under its variant, aside from allowed shared addons/assets. F5 configuration remains untouched. |
| Shared Cogito/input/audio runtime diagnostics | FAIL | The scene invocation logs pre-existing missing `prologue_*` InputMap actions and null stream/add-child/reparent errors in shared input/audio/Cogito addon code, plus resource cleanup warnings. Lab assertions and rendered workflow still complete. Shared addons were left untouched. |
| Human keyboard/mouse session and standalone export | NOT_TESTED | Verification used automated Godot rendered frames and scripted interactions, not exploratory physical input. No exported build was requested or run. |

## Reproduction

1. Open `res://implementations/communication_lab/communication_lab.tscn` with F6. From the spawn point press E near Astera; the interaction range includes the default player spawn. Astera greets and waves.
2. Try `Ich heiße Alex` (or just `Alex` after the opening question), then `Wie geht's dir?` or `Was machst du?` in either order. Try `Sehr gut!`, `Nicht so gut.`, `Ich bin müde.`, `Ich habe frei.`, `Ich arbeite.`, or `Ich lerne Deutsch.` and compare her reply, face/body reaction and F2 diagnostic fields.
3. After Astera mentions being tired, ask `Warum?`; with no relevant context she asks what the player means. After reporting a mood, try `Und du?`; without a mood context it asks for clarification.
4. Try `Kann ich helfen?`, then `Ja, bitte!` and `Nein, danke.` in separate runs. A help offer is remembered, but no cup transfer is simulated. Learning German leads to a slow-speech yes/no question; only yes enables the temporary conversation preference.
5. Try `Bis später!`; Astera uses the farewell motion. Unknown text such as `Ich fliege zum Mond` remains typeable and has no world side effect.
6. Repeat the existing lab checks: `Hallo` while NPC busy/free; `Ja`/`Nein` inside/outside legacy pending offer; `Schlüssel?` then `Wo ist der Schlüssel?`; `Öffne die Tür nicht.`; repeat `Ich brauche den Schlüssel` and inspect effects; reset and continue movement.

New dialogue grammar is intentionally limited to the documented lexical/intent subset. It is not unrestricted German comprehension. The attempt journal records input, parse, before/after state, NPC reply, conversation context, chosen reaction, emotion and animation ID.
