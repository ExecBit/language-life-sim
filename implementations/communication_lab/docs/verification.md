# Issue #68 verification

Run checks from the repository root with the Godot 4.7.1 console executable. This task uses the source project only. It does not build an EXE or PCK and does not use export templates.

| Check | Result | Evidence |
| --- | --- | --- |
| Authored No Pass graph | PASS | `.local/issue68_static_check.js` confirms the 18 required node IDs, 61 unique transitions, four endings, valid action/guard/frame references, declarative consequences, reachability, the seven authored route sequences, and effect-free returns. |
| Initial technician claim and refusal consequences | PASS | The structural check confirms that the first technician claim only records verification, repeated insistence is required for escalation, and refusing Tom's message applies no punishment or access effect. |
| Productive German intent behavior | NOT_TESTED | `tests/test_issue68.gd` and `tests/test_productive_intents.gd` cover role, polarity, alternatives, rules, short answers, and unsupported or compound input. The Godot test runtime crashed before printing assertions, so no runtime verdict is claimed. |
| Godot editor source scan | PASS | `Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --quit` exited 0 with no GDScript parse errors. Godot could not write editor settings under `AppData/Roaming/Godot` and printed save/cleanup warnings in this restricted environment. |
| Runtime acceptance and scene tests | FAIL / no test verdict | The earlier Godot runtime process exited with Windows status `-1073741819` (signal 11) before `test_issue68.gd` printed assertions. The capture script also did not reach its checks. The runtime was not repeatedly retried. Source tests remain in `tests/test_issue68.gd`, `tests/test_productive_intents.gd`, `tests/test_lab.gd`, and `tests/test_issue65.gd`. |
| F2 visual inspection | NOT_TESTED | `tests/capture_issue68_graph.gd` captures the live room and runtime `GraphEdit`, but the Godot runtime crashed before rendering. The updated layout has not been visually verified; no screenshot PASS is claimed. |
| Export / EXE / PCK / templates | NOT_RUN | None were invoked. |

## Reproduction

Open `res://implementations/communication_lab/communication_lab.tscn` in the source Godot project. Use **F6**, approach Astera and press **E**, then **F2**. The graph is built from the same `first_talk.json` transitions consumed by `DialogueGraph` and `LabSession`. Select a node to inspect its conditions and actions, use the zoom controls or drag the canvas to navigate, and use **К текущему** to focus the active node. Submit a supported line to update the route; choose an older attempt under **История** to inspect its read-only graph snapshot. The capture script records the actual F2 viewport to ignored `.local/issue68-f2-graph.png` when the source runtime is working.

Run the source test scripts with Godot `--headless --path . --script res://implementations/communication_lab/tests/<script>.gd --quit-after 600`. A successful process exit alone is not sufficient; check the script's assertion summary and engine errors.
