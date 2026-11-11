# Issue #65 — COMMLAB-03 Stage 2 report

Branch/PR: `codex/issue-62-communication-lab` / [PR #63](https://github.com/ExecBit/language-life-sim/pull/63)

The Stage 1 corpus and oracle were not edited. SHA-256 remains `dev.jsonl` `9a004125f84c9e51f22dc98725e4f2e8ae1f5403b70fb2dcd4f5d592f6ea2044`, `validation.jsonl` `4f4154f86cae665d2f6bdff73bd5ef7dc76238565804be1ad6dd8999d14a2fd1`.

## Generalized changes

| Error family | Root cause in the prior lab resolver | Mechanism and counterexamples |
|---|---|---|
| Help direction, roles and negation | `_parse_clause` treated `kann + helfen` as sufficient evidence, without establishing who helps whom or resolving `nicht` first. | Read nominative and oblique pronoun roles with verb lemma/form; resolve polarity before intent; clarify when roles or speech act conflict. Contrasts: `Ich kann dir helfen` / `Ich kann dir nicht helfen`; `Kann ich dir helfen?` / `Kannst du mir helfen?`; `ich dir helfen` / `ich mochtest helfe du`. |
| Finite form, agreement and recoverable fragments | Intent branches relied on exact lexical cues and did not expose a reusable verb/person/form analysis. | Added a compact data-driven verb morphology table, contextual token normalization and class diagnostics. Recover only when participants and polarity remain clear; examples: `Ich bin müde` / `Du bist müde`; `Du bin müde` keeps the subject and reports agreement; `helfen` without a modal is recoverable only when roles are clear. |
| Pronoun case and word order | Nominative tokens were conflated with semantic roles, while valid German inversion and malformed order were not distinguished. | Use verb position, question structure and case evidence; correct a clear case error, otherwise ask. `Wie geht es du?` preserves the question target and reports case; `Was machst du?` does not get a false word-order error. |
| Negation scope and contradiction | The old intent check could accept a help phrase despite negation. | A negative clause cannot advance `offer_help`; unresolved scope clarifies, and separately parsed intents remain non-executable. |
| Names, unknown words and near forms | Capitalized names could be guessed as known vocabulary, and unscoped fuzzy matching could turn an unknown content word into a nearby token. | Treat a proper noun as a name only in a pending name slot or a name-introduction construction; fuzzy correction is constrained by expected part of speech and a unique nearby form. `Alex` without a name prompt clarifies; `Ich bin erschöpft` and `ich xyz helfen` remain unknown. |
| Ellipsis, context and multi-intent safety | Context-free `Warum?` / `Und du?` could be interpreted as complete turns; a clear prefix could be applied while dropping a continuation. | Bind elliptic questions to topic/pending context. Preserve component frames for understood compounds, return `UNSUPPORTED/MULTIPLE_INTENTS`, and apply no partial goals/effects. |

The only new parser logic is organized around lexical morphology, role assignment, negation, context and clause structure; no condition keys on a corpus string, case ID or expected label. The lab `AGENTS.md` anti-overfitting rules were pushed as the first Stage 2 commit (`928fbc427c088f89a489256fc42997f1dcc1bfff`).

F2 now shows the decision frame and component frames, semantic-recovery completeness, independently detected grammatical error, whether recovery was used, explicit normalized evidence, inferred fields, ambiguity and diagnostics. New clarification/fallback NPC lines have F1 phrase translations. No other variant, emotion/face/animation/avatar asset, or project-wide F5 configuration was changed.

## Metrics

| Split | Baseline decision agreement | After Stage 2 | False acceptances | False rejections | Missed clarifications | Single-intent recoveries with grammatical errors |
|---|---:|---:|---:|---:|---:|---:|
| Dev (200) | 77/200 (38.5%) | 168/200 (84%) | 23 → 0 | 62 → 14 | 36 → 3 | 0/61 → 61/61 (100%) |
| Deferred validation (50) | 16/50 (32%) | 34/50 (68%) | 5 → 4 | 19 → 7 | 9 → 3 | 0/13 → 7/13 (54%) |
| All cases (250) | 93/250 (37.2%) | 202/250 (80.8%) | 28 → 4 | 81 → 21 | 45 → 6 | 0/74 → 68/74* |

`*` The all-case recovery column includes validation’s independently defined recoverable subset (13) plus dev (61); it is not a blind-test claim. The authoritative target comparison is dev 61/61 and deferred validation 7/13.

Dev grammatical diagnostic evidence is 65/65 expected cases, with one unexpected diagnosis and no missing diagnosis. Role mismatch on dev increased 87 → 99 despite role swaps decreasing 3 → 1 overall; overall role mismatch is 110 → 129. This is a material unresolved weakness. Dev objective-advancement mismatches decreased 70 → 15; overall negation loss decreased 6 → 0.

Validation was run once after the parser freeze. Its four false acceptances include compound utterances that the current clause splitter did not preserve as unsupported compounds, plus negation/scope and speech-act classification errors. The recoverable validation grammar classes remain below target, including missing-modal/finite-form, case and word-order examples. These are failure classes to address only with a new independent validation set or user-reviewed evaluation; no post-validation tuning was done.

## Verification

- PASS — `test_issue65.gd`: 20 targeted counterfactual assertions; 0 failures.
- PASS — `test_lab.gd`: 116 assertions; 0 failures, exit 0. The Godot process still logs shared Cogito null-node (`Audio.add_child`, reparent) and resource-cleanup errors/warnings at shutdown.
- PASS — Stage 2 corpus runner: all 250 cases and original distribution validated; no corpus integrity failures. Dev and validation summaries are separate.
- PASS — dev target: zero false acceptances and 61/61 single-intent recovery cases.
- FAIL — deferred validation target: 4 false acceptances and 7/13 (54%) single-intent recoveries; role mismatch regressed. See metrics above.
- PASS — parser `--check-only` validation. The full headless editor scan completed without script parse errors, but Godot reported an environment `Safe save failed` and existing ObjectDB/resource cleanup errors; do not treat the editor exit as a clean PASS.
- NOT_TESTED — manual GUI/F6 play session and visual inspection. Headless parser/session tests cover changed semantics; no GUI run was needed for this parser-focused change.
- PASS — F1 helper translations for new clarification lines are covered by the targeted test.
- PASS — no inference server was started or restarted; no corpus expected values were changed.

### Validation-isolation note

A first `--dev-only` runner attempt also invoked fixed corpus-contract checks for two validation IDs. The harness was then corrected so dev-only runs skip validation-only fixture checks. Those exposed rows were not used as targets for parser rules. The deferred 50-case validation above was run once after the final parser freeze; no changes to parser or gold data followed it.

## Result

**Overall acceptance: FAIL** because deferred validation misses the zero-false-acceptance and ≥90% recovery goals, and role mismatches regress. Dev behavior and safety improved substantially, but this is not a passing Stage 2 result. No gold labels were edited. The implementation and this report are pushed to the existing PR #63 for review; it remains unmerged.

