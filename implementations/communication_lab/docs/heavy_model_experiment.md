# 9–12B experiment: model size and dialogue context

The user authorized larger local models after LFM3-1.7B and Granite 4.2-3B failed the semantic gate. This continues Issue #68 in PR #63; no Godot export, new PR or merge. The experiment concerns interpretation of player utterances, not free generation of story outcomes.

## Research and selection

| Candidate | Why considered | Decision |
| --- | --- | --- |
| [Qwen3.5-9B](https://huggingface.co/Qwen/Qwen3.5-9B) | 9B, multilingual post-trained model, published instruction-following evaluations, configurable non-thinking mode; Apache 2.0. | Test as the main 9B candidate. Use only text; no vision projector. |
| [Mistral NeMo Instruct 2407](https://huggingface.co/mistralai/Mistral-Nemo-Instruct-2407) | 12B multilingual instruction model with published German evaluation, mature architecture; Apache 2.0. Older, but relevant to German and structured interpretation. | Test as a 12B comparison, not selected on release date. |
| [Rocinante 12B v1.1](https://huggingface.co/TheDrummer/Rocinante-12B-v1.1) | NeMo-derived community adventure/RP model. Its author emphasizes richer prose/creativity and supports ChatML, Alpaca and Mistral formats. | Researched, not downloaded. Those claims do not establish better German intent extraction. Card declares `license: other`; do not assume the base model's Apache license automatically resolves the derivative's terms. |

Published benchmarks and community positioning are selection evidence, not proof on this game's utterances. No public RP leaderboard score is presented as a German semantic accuracy score.

[SillyTavern's Prompt Manager](https://docs.sillytavern.app/usage/prompts/prompt-manager/) separates character/scenario information, dialogue history and instructions, and explicitly discusses speaker association. This is useful prompt construction practice. A long “stay in character” instruction alone does not validate roles, negation or consequences. Here Astera's authored replies and graph retain authority; the model interprets speech rather than inventing a new story.

## Confirmed prompt defect and controlled comparison

The original `prompt_input()` passed NPC wording only inside a nonempty pending proposition. At the opening/name/registration nodes it omitted the actual last NPC reply. It never passed recent utterance/reply history. This is a confirmed omission in the request builder; its contribution to previous model failures is a hypothesis, not a proven sole cause.

Mechanism: add explicit speaker roles, always include the last NPC reply, the last four actual player/NPC exchanges, relevant world facts and the existing pending proposition. Treat all of these as reference data. The player's newest utterance remains a separately named data field; it is the only text classified. Do not filter the meaning vocabulary to available story actions, and do not send the selected menu goal as the answer to predict.

Contrasts: player→NPC help versus NPC→player help; missing possession versus negative desire; role assertion versus role wish/question; affirmative identity versus a different name. Risks: world facts could bias classification of deliberate lies, history could contaminate the current utterance, or JSON constraints could conceal semantic mistakes. The expanded driver checks these classes, all authored routes, and explicit non-execution of unsupported/compound meanings. It contains no runtime recognition rules.

An independent integration defect was observed during the first expanded run: valid FAREWELL model output was rejected before graph resolution because `_candidate()` omitted the required `speaker` field. `actor` describes the action participant; it does not replace the provenance of who submitted the utterance. The generalized correction supplies speaker identity from the scenario participant declaration for every model candidate, without changing the model's semantic label or adding a phrase rule. Contrasts: valid farewell may take its authored leave edge; unrelated/unknown output still cannot create an edge. A boundary regression was added before the correction. Final model/temperature comparisons use the corrected common adapter; initial artifacts are retained separately. This defect must not be reported as a model language error.

Two request versions are compared with each model's same weights, sampler and seed:

- `baseline-v1`: the previous system instruction + minimal reference context in system; raw German in user.
- `context-v2`: detailed interpretation contract + intent definitions in system; user JSON containing `reference_context` and `player_utterance`.

The same real-model 12/13-request driver is used first. The expanded development probes are declared before either new model is run. A failed route stops instead of counting subsequent steps as independent failures. This is a targeted development experiment, not a blind benchmark or an estimate of unrestricted German understanding. The deferred historical 50-case validation set is not used or tuned against.

The user additionally requested a temperature comparison. With `context-v2` fixed, test 0.1, 0.7 and 1.0 for both larger models; keep seed 62, top_p and all other settings unchanged within each model. Record each run separately rather than overwriting results or selecting only a favorable answer. This isolates temperature within a model, not all sampler differences between models. Single seeded runs do not measure stochastic reliability.

## Exactly what is sent

One local POST to `http://127.0.0.1:38173/v1/chat/completions` per submitted utterance:

1. `system`: interpreter role, ownership of first/second person, negation/modality/compound rules, clarification policy, output contract and scenario-owned English label definitions. No fixture examples or expected answers.
2. `user`: JSON with `player_utterance` (original German, unchanged) and `reference_context`:
   - `speakers`: player/user and NPC/Astera;
   - `npc_last_reply`: actual most recent NPC wording, including a clarification;
   - `recent_dialogue`: at most four `{player, npc}` pairs from actual session history; no old model prompts, predictions or reasoning;
   - `pending_proposition`: its ID/kind/value and actual question wording;
   - `name_requested`, `discussed_objects`, `challenged_role`: scenario-authored discourse declarations;
   - `world_facts`: current player name, registration/technician/pass/access/promise/trust facts, explicitly distinguished from what the player may assert.
3. `response_format`: JSON Schema with enum `intent`, string `name`, boolean `needs_clarification`, string `clarification`. Schema validity is not a guarantee of semantic truth.
4. Actual model alias, sampler, seed 62, output limit and chat-template kwargs. llama.cpp's `--jinja` applies the embedded model template. No manual ChatML tokens are concatenated into the German text.

The model receives no full graph, transition IDs, effects, Russian selected goal, fixture labels, files, F1 browsing history or other variants' state. The current pending question's ID is reference for answer binding, not permission to execute an edge. Requests stay local; remote access is only for downloading public model assets.

Dialogue history is quoted reference JSON, not a sequence of API assistant messages pretending this classifier previously spoke as Astera. The API assistant's job is to return meaning JSON; Astera's German speech is authored game data. This separation keeps those two roles explicit. A future experiment may compare other history encodings, but this run does not claim that one encoding is universally optimal.

Full actual `model_request`, decoded response, token usage, backend, prompt version and latency are saved with the interpretation in session diagnostics/JSONL. F2's analysis tab displays the actual request. Live test artifacts in ignored `.local/lfm3/*-results.json` contain requests; these include player text and names. The request builder copies only dialogue strings from past events, preventing recursive inclusion of earlier requests. Infrastructure failures before a request naturally have no inference payload.

## Assets and settings

Pinned file revisions, byte sizes and SHA-256 digests are in `data/communication/lfm3_manifest.json`; both new models are Q4_K_M. These are community conversions of the linked upstream weights, not vendor-authored GGUFs. All downloads stay in ignored `.local/lfm3/`. The pre-existing pinned llama.cpp b12110 Vulkan runtime is reused.

- Qwen: 5,680,522,464 bytes of weights. Non-thinking, temperature 0.7, top_p 0.8, top_k 20, min_p 0, presence_penalty 1.5, following its card's non-thinking general-task defaults. No `/nothink` text switch (the card explicitly does not support that switch).
- NeMo: 7,477,208,192 bytes of weights. Non-thinking, temperature 0.35 as its official usage example, top_p 0.95. Embedded Mistral chat template.
- Both: one inference slot, 4096 context tokens, at most 600 output tokens, 60-second request timeout. These are deliberately bounded interactive settings; not maximum-context benchmark settings. Weight size is not total VRAM usage.

An additional `qwen9-thinking` profile tests the same weights with the vendor's documented general thinking defaults (temperature 1.0, top_p 0.95, same top_k/min_p/presence penalty), an 8192 context and 2048 output budget. It is a separate reasoning-mode experiment, not part of the fixed non-thinking temperature comparison. The budget remains much smaller than the vendor's complex-task benchmark budget; record truncation/timeouts rather than treating them as semantic predictions. No prompt or phrase-specific rule changes accompany this test.

## Reproduction

```powershell
python implementations/communication_lab/tools/setup_lfm3.py --model qwen9
python implementations/communication_lab/tools/setup_lfm3.py --model nemo12
$env:COMMLAB_LANGUAGE_MODEL = 'qwen9' # or nemo12
$env:COMMLAB_PROMPT_VERSION = 'baseline-v1' # then context-v2
& $engine --headless --path . --script res://implementations/communication_lab/tests/test_lfm_live.gd --quit-after 90000
$env:COMMLAB_PROMPT_VERSION = 'context-v2'
$env:COMMLAB_TEMPERATURE = '0.1' # repeat with 0.7 and 1.0
& $engine --headless --path . --script res://implementations/communication_lab/tests/test_heavy_language.gd --quit-after 90000
```

Both model profiles are experimental and initially disabled. Test drivers explicitly call the model. For interactive source play, set `$env:COMMLAB_LANGUAGE_MODEL_ENABLED = '1'` together with the model selection before launching Godot (or enable the selected profile for an F6 editor session). No tracked config edit is needed for the environment opt-in. An unavailable enabled backend never silently becomes the grammar parser. Closing the source scene stops only its owned inference child. Shared Kimodo services are unrelated and untouched.

```powershell
$env:COMMLAB_LANGUAGE_MODEL = 'qwen9'
$env:COMMLAB_LANGUAGE_MODEL_ENABLED = '1'
$env:COMMLAB_TEMPERATURE = '0.1'
& $engine --path . --rendering-method gl_compatibility res://implementations/communication_lab/communication_lab.tscn
```

This is the source scene launched by the installed Godot engine, not an exported game. E near Astera opens dialogue; F2 → Разбор shows the actual model request. Clear the opt-in environment variable before launching a normal offline session.

## Observed non-thinking results

Short-driver prompt ablation (failing assertions, not independent accuracy rates):

| Model | Baseline v1 | Context v2 | Requests per run |
| --- | ---: | ---: | ---: |
| Granite 4.2-3B, vendor low-effort reasoning | 2 (previous run) | 0 | 12 |
| Qwen3.5-9B, temperature 0.7 | 1 | 0 | 12 |
| NeMo 12B, temperature 0.35 | 4 | 1 | 12 |

Thus context construction matters, and the short driver is insufficient: passing it did not predict passing the expanded probes. Granite's first expanded v2 run failed 11 assertions, including the subsequently corrected adapter farewell defect; it is historical diagnosis, not a fair final score against the corrected larger-model runs.

Final common-adapter `context-v2` temperature comparison:

| Model | Temperature | Meaning failures / 22 contrasts | Interrupted authored routes | Missing-object repair failure | Total failing assertions | Real requests | Warm median latency |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen 9B | 0.1 | 4 | 0 | 1 | 5 | 57 | 399 ms |
| Qwen 9B | 0.7 | 2 | 1 | 1 | 4 | 54 | 407 ms |
| Qwen 9B | 1.0 | 3 | 1 | 1 | 5 | 54 | 404 ms |
| NeMo 12B | 0.1 | 3 | 1 | 1 | 5 | 54 | 508 ms |
| NeMo 12B | 0.7 | 5 | 1 | 1 | 7 | 54 | 515 ms |
| NeMo 12B | 1.0 | 7 | 1 | 1 | 9 | 54 | 461 ms |

Latency is client wall time after excluding the first request of each run (which includes model startup). It is a sampled local result on this machine, not a hardware-independent guarantee. The final requests reached at most 1160 Qwen / 1241 NeMo prompt tokens; the context window did not truncate those inputs. A route abort changes the number of subsequent requests, so do not divide total failures by request count and call it language accuracy.

Qwen 0.1 completed all eight authored paths including contextual name answers and remembering both successful endings. It still mapped a negative desire to a message refusal, a role wish to an assertion, and a second-person possession statement to an unrelated player-role denial. At 0.7 the role wish improved, but the rules question was misclassified; increasing temperature did not establish reliability. NeMo also had negation/role/modality errors; its best tested temperature was 0.1, not a complete solution.

Both non-thinking models failed the required contextual proposal for `ich möchte vorläufigen`: they asked an open/unspecific clarification rather than holding a pass-request candidate that an immediate yes could confirm. That failure is distinct from falsely granting access. No production phrase rule was added to repair the metric.

Windows `Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory` samples during inference reported approximately **5.26 GiB dedicated GPU memory for Qwen** and **7.64 GiB for NeMo** on the RX 7900 XTX; Granite's reference sample was 2.54 GiB. These are process samples (including a negligible secondary-adapter allocation), not measured peaks, reserved total device memory, or the combined game+model budget. Raw samples are `.local/lfm3/*-memory-inference.json` (Granite: `granite-memory.json`).

## Reasoning mode: bounded response failures

The full Qwen thinking run was interrupted after repeated output-budget exhaustion; it is **not a completed route evaluation**. A separate six-probe run retained actual requests, finish reasons and usage:

- Two role-direction questions returned the correct meanings, using 977 and 1096 completion tokens, in roughly 11–13 seconds.
- Four subsequent simple polarity/possession statements each consumed all 2048 completion tokens and returned `finish_reason: length`; the client correctly returned `INCOMPLETE_MODEL_RESPONSE` without executing an action. These are **response-budget failures**, not four observed wrong semantic labels.
- Warm median client latency: 20.7 seconds. Sampled dedicated GPU memory: 5.38 GiB. All remaining semantic probes and all eight routes in this mode are **NOT_TESTED**.

The completed six-probe artifact is `qwen9-thinking-q4_k_m-t1.00-limited-results.json`; interrupted logs use `qwen9-thinking-interrupted*`. Reproduce the bounded probe with `COMMLAB_LANGUAGE_MODEL=qwen9-thinking`, `COMMLAB_PROBE_LIMIT=6`, temperature 1.0 and the expanded driver. Clear `COMMLAB_PROBE_LIMIT` for a full run. Increasing the output budget might produce final answers but was not tested; no claim is made that this model can never solve those meanings. Under the tested interactive budget it is unsuitable.

## Interpretation and acceptance

No tested setting passes the complete gate. Keep all profiles disabled by default. Qwen 9B non-thinking is the more useful continuation candidate on these observations; 0.1 completed the authored routes, while 0.7 had fewer isolated contrast failures but interrupted a route. Neither result warrants a reliable-understanding claim or an automatic production switch. More parameters, a more elaborate prompt or a different temperature alone did not establish that claim.

The experiment fixes two actual integration defects (missing dialogue context and missing speaker provenance), preserves the authored graph's authority, and makes requests inspectable. It does not add phrase-specific parser patches, change oracle labels, or turn known model failures into passing expectations.

Source verification: boundary/request/lifecycle checks PASS (including a reproduced farewell failure before the fix); existing 94 offline semantic assertions PASS; existing eight-route graph test PASS; default offline source-scene test PASS. Rendered actual source scene with Qwen 9B / temperature 0.1: Composer → real model → G10_NO_CARD → actual F2 graph/history PASS for transport, and the capture was visually inspected. This is not an additional broad language-quality PASS. The capture is `.local/lfm3/qwen9-q4_k_m-source-model-graph.png`; its log contains the actual request and response.

Known shared quick_audio/Cogito null-node errors and shutdown resource warnings remain visible; shared addons were not modified. All inference processes created by these tests were stopped, including the explicitly interrupted reasoning run. No export, game EXE/PCK, export template or merge operation was performed.
