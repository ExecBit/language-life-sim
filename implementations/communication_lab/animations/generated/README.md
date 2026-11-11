# New Communication Lab motions

Twelve new clips generated on 2026-11-11 using the already-running local Kimodo service, SOMA RP v1.1 and Q8_0 text encoder. No inference process was started, restarted or stopped by the agent. No previously generated prologue output is used.

`manifest.json` contains selected job IDs, exact prompts, seeds, frame counts and model settings. `requests.json` retains the first and revised prompts. Eight first-pass candidates were rejected after rendered review because their gestures did not match the requested physical actions closely enough; rejected binaries are ignored in `.local/`.

Outputs are generated motion skeletons, not character models. Model: nvidia/Kimodo-SOMA-RP-v1.1, NVIDIA Open Model License: https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/ . No model weights or private Astera VRM are included.

Each selected clip has 120 frames at 30 FPS (approximately four seconds), 100 diffusion steps, and five transition frames. The adapter retargets onto Astera and blends back to the existing idle. Facial expressions are controlled separately; motion generation does not produce VRM facial expressions.

## Validation

PASS: all twelve GLBs imported and retargeted on the local Astera; sampled rendered frames inspected at 0.3, 1.5 and 3.0 seconds. PASS: automatic return to idle checked by the preview runner. Rendering uses `--path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/preview_generated.gd`. Captures/logs stay in ignored `.local/`.

The clips are reviewed candidates for scene integration, not a claim of final cinematic quality. The curious motion includes a hand-near-face listening gesture. The point gesture requires staging the cup on the character's right; exact prop alignment and phrase timing remain NOT_TESTED until scene integration. No hand IK or foot locking is added. Existing Cogito audio initialization/resource cleanup errors remain in CLI runs.
