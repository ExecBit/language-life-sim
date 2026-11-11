# Issue #62 verification report

## Targeted automated checks

| Check | Result | Reproduction |
| --- | --- | --- |
| Headless Godot import | PASS | Godot 4.7.1: `--headless --path . --editor --quit` exited 0 after filesystem scan/import. The restricted host profile caused a safe-save warning; assets and scripts completed scanning. |
| Parser/resolver and scene-state cases | NOT_TESTED | Attempted `--headless --path . --script res://implementations/communication_lab/tests/test_lab.gd`; the installed Godot 4.7.1 process crashed with signal 11 before test output. A plain `--headless --path . --quit-after 5` launch crashed the same way, indicating an engine/runtime failure rather than a test assertion result. The suite now contains the additional HUD/panel/avatar/idle assertions for rerun in a working Godot runtime. |
| Variant isolation scan | PASS | No `res://implementations/dormitory/` references in lab scripts, tests or scene. F5's `project.godot` entry remains the dormitory scene. |
| F6 scene startup after Astera/HUD update | NOT_TESTED | Current Godot CLI launch is blocked by the same signal 11 crash; no startup result is claimed for this follow-up. |
| Updated visual composition and real input | NOT_TESTED | Headless checks confirm Astera is selected when the local private VRM exists, the retargeted idle animation is active, Cogito HUD is hidden, and the Communication panel is anchored bottom-left. No screenshot or GUI interaction was run for this follow-up, so appearance, dialog input, movement lock, diagnostics and reset were not visually rechecked. On clean checkouts, the private Astera VRM is absent and the redistributable Anna fallback is selected. |
| F5 default startup | PASS (headless) | `--headless --path . --quit-after 120`; default dormitory started and its Motifect actors initialized. |
| Export and candidate launch | NOT_TESTED (attempt blocked) | `--export-debug "Windows Desktop" .local/communication_lab_candidate.exe` found no root `export_presets.cfg`; Godot also reported the VRM extension DLL unavailable. No candidate was produced. |

## Reproducible phrase fixtures

- `Hallo` with Anna free and busy: compare contextual response.
- `Ja` with and without a pending offer: only pending state recognizes it as an answer.
- `Schlüssel?`, then `Wo ist der Schlüssel?`: fragment needs clarification; complete question resolves its location.
- `Öffne die Tür nicht.`: no door effect.
- `Ich brauche den Schlüssel` with the key at Anna, elsewhere, and Anna busy: only the available/free context transfers it.
- `Ich brauche den Schlüssel` twice: transfer occurs once.
- `Kannst du die Tür öffnen?` with Anna free and busy: only the free context opens the door.
- `Ich will Flöte.`: free text is accepted by input and reports an unknown token.

## Limitations

The parser is copied without grammar changes; its internal proper-noun vocabulary and addressee ID remain Anna. The room resolver supports only explicit social responses, key location/transfer, door opening, and safe acknowledgements. It does not promise free-form German comprehension. The earlier headless runs emitted Cogito warnings about rendering-device-dependent input icons and resource cleanup but exited 0; the current follow-up rerun crashes as noted above. No interactive movement, dialog, export or exported-build result is claimed.
