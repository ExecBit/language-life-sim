# Communication Lab — local agent instructions

Root `AGENTS.md` and the authorized Issue remain the contract. Read the whole Issue, including additions. Continue the existing authorized branch/PR; do not treat an intermediate asset milestone as completion of the whole task. This file describes reusable tooling, not task status.

## Kimodo: use the running service; never start inference

- The user starts inference. Never launch, restart, stop, install or reload the inference server/model, including through launcher scripts. Do not generate a new character model.
- Generation requests to the already-running service are allowed when the user authorizes motion generation. Fetching a GLB or inspecting its API does not require starting inference.
- Do not substitute former generated outputs when the user asks for new animations. Generate new jobs and retain their IDs. Existing outputs can be inspected as references.

### Discover the actual client contract before declaring a blocker

1. Obtain the service address from its existing configuration/logs or the user. The verified local address on 2026-11-11 was `http://127.0.0.1:8094`; `.local/kimodo-server/stdout.log` recorded it. Do not guess ports.
2. GET `/` and inspect referenced scripts. **Read `/models.js` too:** it wraps the simple page's `fetch` and adds model, text encoder and sequence parameters. Reading only the inline `/api/generate` handler is incomplete.
3. GET `/api/models` and `/api/text-quantizations`; choose entries whose `available` is true. The verified pair was `soma-rp-v1.1` and `q8_0`. Check again each session rather than assuming availability.
4. **Always send `model` and `text_quantization` explicitly.** Omitting them previously selected unavailable `smplx-rp-v1` and produced `GGUF not found at models/kimodo-smplx-rp-v1-f32.gguf`, even though SOMA and Q8_0 were available. This error alone does not mean inference is unavailable or weights must be installed.
5. If a sandbox forbids local sockets, request the execution permission needed for the authorized HTTP operation. Do not misreport an access denial as a stopped service. Permission to contact the service does not authorize launching it.

### Verified API and request shape

Confirm these against the running UI before use if the service changes:

```json
{
  "model": "soma-rp-v1.1",
  "text_quantization": "q8_0",
  "prompt": "A standing person gently nods once, then returns to neutral. Feet planted.",
  "frames": 120,
  "steps": 100,
  "seed": 42,
  "transition_frames": 5,
  "segments": [
    {"prompt": "A standing person gently nods once, then returns to neutral. Feet planted.", "frames": 120}
  ]
}
```

- POST JSON to `/api/generate`. The response supplies the new job `id` and status. Use stop-on-error handling; never print success or store an empty ID after a failed request.
- The UI accepts 60–150 frames per segment. These outputs use 30 FPS. Record requested and returned settings; do not assume the prompt guarantees the motion.
- GET `/api/animations` to poll the submitted IDs (`queued`, `running`, `ready`, or an error). Use bounded polling and keep communicating during long runs. Do not regenerate an accepted job merely because it is still queued.
- Download a ready job from `/api/animations/{id}/animation.glb`.
- If the service is unreachable or no suitable model/encoder is available, stop generation and report the precise error and availability results. Do not start a server or silently replace new generation with old clips. Continue independent authorized work unless the user explicitly prioritizes completing animations first.

## Asset placement, provenance and quality

- New lab outputs belong in `animations/generated/` under this variant. Include the motion key and job ID in filenames. Keep rejected candidates, raw API responses, logs and screenshots in ignored `.local/`.
- Keep exact English prompts, seed, frames, steps, transition frames, model, encoder, job ID, license/provenance and selected filename in the committed manifest. See [the motion manifest](animations/generated/manifest.json) and [generation notes](animations/generated/README.md) for the format.
- Prefer concise physical actions: which limb moves, direction, tempo, stable feet, start/end pose. Differentiate physical motion from facial emotion. A prompt saying “smiles” does not generate VRM facial expressions.
- Import and retarget onto the actual Astera before accepting a clip. Inspect the gesture, feet, hands, intersections, root motion, start/end and idle transition. Regenerate motions that do not convey the requested action; a `ready` job is only a generated candidate.
- Use [the preview runner](tests/preview_generated.gd) for rendered samples and return-to-idle assertions. It reads the committed manifest. Capture logs/images in `.local/`.
- Samples and an idle-transition assertion do not establish continuous-motion polish, exact prop alignment or timing with speech. Report those checks separately and honestly. Do not mark the whole Issue complete after generating a library.
- Keep the private Astera VRM and its import settings uncommitted. Other implementations and global assets must not be modified for this variant.

## Godot verification

Use the installed **console** executable to wait for completion and capture logs, e.g. `Godot_v4.7.1-stable_win64_console.exe`. The GUI executable can return before the engine finishes. Resolve its actual path with `Get-Command` if `godot` is absent from PATH.

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --quit
Godot_v4.7.1-stable_win64_console.exe --path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/preview_generated.gd --quit-after 300
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd --quit-after 120
```

Headless/CLI validation and automated renders are the default. Never infer PASS from exit code alone: check assertion summaries and script errors. Existing Cogito audio/cleanup errors must remain visible in reports. Do not change shared addons merely to hide them.
