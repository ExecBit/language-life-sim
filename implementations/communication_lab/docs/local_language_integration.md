# Local language-model integration — experimental

**Neither tested model is accepted as the primary recognizer. Both profiles are disabled by default.** The source scene keeps the existing offline recognizer unless a model profile is explicitly enabled. A successful HTTP request is not a successful language-understanding result.

The user authorized LFM3 integration and then a comparison with another compact model. This supersedes the original Issue #68 exclusion of external LLMs for this change only. The existing branch/PR, source-only verification and no-merge/no-export constraints remain. Kimodo and its inference process are unrelated and were not changed.

## What is connected

`Composer → asynchronous Local HTTP client → llama.cpp → constrained JSON meaning → LabSession.submit_interpreted → guarded runtime graph`.

The client sends the player's text as a separate user message. NPC question, pending proposition and relevant referents are reference context. Domain descriptions live in `first_talk.json` under `language.intent_descriptions`; German input is not matched against those descriptions or a whitelist of utterances. Returned intent labels must have one declarative meaning in `language.bindings`. Their canonical frames are constructed from those declarations; name and confirmation binding use the current proposition. A model cannot supply effects, edge IDs or arbitrary state changes. This limits execution, but **does not prove a chosen semantic label is correct**.

The model request does not freeze the main thread. Duplicate Enter is blocked while pending. Closing/resetting the dialogue increments a request generation; late responses cannot affect the new session or add a phantom history event. Server/malformed-output failures do not silently invoke the offline grammar. F2 records backend, actual decoded model output, latency and token usage alongside the real graph/event history. Generated clarification words must be available in F1; otherwise the existing short fallback is used.

The source scene lazily starts only its own pinned llama.cpp child on first model request, bound to `127.0.0.1:38173`, with one slot and a 4096-token context. It reuses an existing server only if its model alias matches. On scene exit it terminates only the child PID it created. Merely opening the default source scene does not load either experimental model or reserve their VRAM.

## Reproduce

From the repository root, Python 3.11+ with no extra packages:

```powershell
python implementations/communication_lab/tools/setup_lfm3.py
# Optional, separately authorized comparison model:
python implementations/communication_lab/tools/setup_lfm3.py --model granite
```

The setup verifies pinned SHA-256 values for the runtime archive and model. Downloads, chunks, binaries, license/card copies and weights remain in ignored `.local/lfm3/`; none are committed. It neither exports Godot nor installs a replacement global runtime.

Profiles:

- `data/communication/lfm3.json`: LFM3-1.7B, official QAD Q4_0. `enabled:false`.
- `data/communication/granite.json`: Granite 4.2-3B, Q4_K_M, vendor-documented low-effort reasoning. `enabled:false`.
- Set `COMMLAB_LANGUAGE_MODEL=granite` before starting Godot to select the comparison profile. Otherwise LFM3 is selected. For a deliberate experimental play session set `enabled:true` in the selected profile, open `communication_lab.tscn`, press F6 and talk to Astera. Restore `enabled:false` afterward. Backend failures are reported in the notice/F2.

The live quality driver calls the real model even when the scene's default profile is disabled:

```powershell
& $engine --headless --path . --script res://implementations/communication_lab/tests/test_lfm_live.gd --quit-after 90000
$env:COMMLAB_LANGUAGE_MODEL = 'granite'
& $engine --headless --path . --script res://implementations/communication_lab/tests/test_lfm_live.gd --quit-after 90000
```

This driver intentionally fails on unresolved language-quality problems. Do not replace its expectations with current model predictions. Network-restricted sandboxes require permission for loopback TCP; the initial isolated run could not contact its local server. That transport failure is distinct from the later semantic failures with real model responses.

## Assets and observed limits

Pinned llama.cpp: `b12110`, from the official `v0.9.0` release's nightly tag, Windows x64 Vulkan build, MIT license. Exact URLs/digests are in `data/communication/lfm3_manifest.json`.

| Model | Weights | Observed result |
| --- | --- | --- |
| Liquid AI LFM3-1.7B, ordinary Q4_K_M | 1,099,627,808 bytes | Rejected: wrong roles/negation and contextual answers. |
| Liquid AI LFM3-1.7B, official QAD Q4_0 | 1,049,615,680 bytes | Rejected: QAD did not resolve the meaning failures. |
| IBM Granite 4.2-3B, Q4_K_M, non-thinking | 2,244,011,552 bytes | Rejected: contextual identity/role errors and partial execution of compound input. |
| IBM Granite 4.2-3B, same weights, low-effort reasoning | 2,244,011,552 bytes | Original player's route reached official access, including full name confirmation. Still rejected: `Kann ich dir helfen?` became REQUEST_HELP; compound no-card + technician input executed only the no-card part. |

The final common-contract LFM3 run reported 4 failing assertions over 12 requests. Granite low-effort reported 2 failing assertions over 12 requests. These are not independent per-utterance error rates: route failures can cascade, and some checks concern effects rather than classification. These are targeted development observations, not an accuracy benchmark. Initial catalog-heavy output was also unreliable; simplifying the response contract and separating NPC context improved some cases but did not remove the critical errors. Small-model reasoning was checked: LFM3 could exhaust the short token budget; Granite's documented low-effort setting improved the original route. No individual German phrase was added as a production recognition rule, no corpus gold was changed, and deferred corpus validation was not run.

Weight-file size is not total VRAM consumption. Context, working buffers and the source game need additional memory. The fixed 4096-token context avoids loading the models' maximum context, but a measured total VRAM claim is not made here. All model processes started by these scene runs were stopped on exit.

LFM3 is under the **LFM Open License v1.0**, including its commercial-use revenue condition and redistribution notice requirements; it is not Apache/MIT. Granite is Apache 2.0. See the pinned manifest and downloaded license copies before redistribution. This change distributes integration source and provenance, not the weights.

The existing quick_audio/Cogito null-node errors and shutdown leak warnings remain visible in source scene runs. They were not suppressed by modifying shared addons.
