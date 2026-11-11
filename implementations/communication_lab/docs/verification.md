# Issue #62 verification report

## Targeted automated checks

| Check | Result | Reproduction |
| --- | --- | --- |
| Headless Godot import | PASS | Godot 4.7.1: `--headless --path . --editor --quit` exited 0 after filesystem scan/import. The restricted host profile caused a safe-save warning; assets and scripts completed scanning. |
| Parser/resolver cases | PASS (32/32) | `--headless --path . --script res://implementations/communication_lab/tests/test_lab.gd`; covers R01–R15/W01–W07, frame fields, no-effect cases, repeat transfer and reset. |
| Variant isolation scan | PASS | No `res://implementations/dormitory/` references in lab scripts, tests or scene. F5's `project.godot` entry remains the dormitory scene. |
| F6 scene startup | PASS (headless) | `--headless --path . res://implementations/communication_lab/communication_lab.tscn --quit-after 120`; scene and idle retarget adapter loaded without script errors. |
| F6 visual/input checklist | NOT_TESTED | The visible F6 launch rendered the room, Anna, key, table and door, but initially exposed a T-pose. The idle adapter was then fixed and headless-checked. The user stopped further desktop checks before the updated pose, dialog, movement lock, diagnostics, reset and composer could be manually repeated. |
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

The parser is copied without grammar changes. The room resolver supports only explicit social responses, key location/transfer, door opening, and safe acknowledgements. It does not promise free-form German comprehension. Headless engine runs emit Cogito warnings about rendering-device-dependent input icons and resource cleanup; they still exited 0. No interactive movement, dialog, export or exported-build result is claimed.
