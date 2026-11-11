# Issue #64 Stage 1 — parser baseline

## Result

**Fixture and runner integrity: PASS. Semantic baseline: FAIL by design.** The runner executed the fixed 250-case oracle against the unchanged Communication Lab parser/resolver/session path. The baseline is a measurement, not a parser acceptance target.

| Check | Result |
| --- | --- |
| Fixture JSONL, unique IDs, per-case shape and required probes | PASS — 250 cases |
| Group counts A–E | PASS — 50 / 80 / 60 / 40 / 20 |
| Stratified dev / validation | PASS — 200 / 50 (dev 40/64/48/32/16; validation 10/16/12/8/4) |
| Gold-label review | PASS — 217 case-level expected labels corrected and recorded; changes await user review |
| Baseline runner | PASS — 250 cases, exit 0; semantic mismatches are reported as findings |
| Repeatability | PASS — two runs produced identical JSONL and summary SHA-256 hashes |
| Communication Lab regression suite | PASS — 106 PASS assertions, 0 FAIL assertions, exit 0 |
| Production parser/session unchanged | PASS — no production communication logic was edited |

Gold changes, original labels, corrected labels and linguistic reasons are listed in issue64_gold_review_ledger.md. The ledger also explains same-group/split replacements. Those changes are not self-approved and remain for user review.

## Semantic baseline

Decision agreement is **95/250 (38%)**. This is separate from full semantic agreement: a status match alone does not establish that the actor, recipient, polarity, speech act, diagnostic/recovery result, clarification quality, or objective progression is correct.

| Metric | Overall | Development (200) | Validation (50) |
| --- | ---: | ---: | ---: |
| Decision match | 95 (38%) | 78 (39%) | 17 (34%) |
| Intent match | 52 | 44 | 8 |
| Full semantic frame match | 10 | 7 | 3 |
| False acceptance | 27 | 23 | 4 |
| False rejection | 86 | 66 | 20 |
| Missed clarification | 47 | 38 | 9 |
| Clarification with wrong reason | 14 | 11 | 3 |
| Clarification lacking candidate output | 14 | 11 | 3 |
| Actor/recipient mismatch | 115 | — | — |
| Role reversal | 4 | — | — |
| Polarity mismatch | 138 | — | — |
| Lost negation | 6 | — | — |
| Incorrect objective advancement | 90 | 73 | 17 |
| Unknown vs unsupported decision confusion | 19 | — | — |
| False help offer | 6 | — | — |
| Negative help parsed as offer | 2 | — | — |

The parser has no candidate_interpretations field. The runner records this as NOT_EXPOSED / unsupported by the current parser, never as an empty but correct candidate set. Candidate output was unavailable for 61 oracle clarification cases; 14 were actually returned as clarifications, so those 14 are insufficiently informative rather than credited as correct.

A high-risk case, Ich kann nicht helfen, must remain negative and must not advance offer_help. The unchanged parser incorrectly recognized two negative-help utterances as offers.

## Fixture and run hashes

- dev.jsonl: 3f04c65efabb646de7dda15d884558eee57dbd3b3682bf99fce7425bf6a11f97
- validation.jsonl: ba793fe0573ce5951dacabfbcb2839efa98728559915de71193e3010b3326eca
- Baseline dev results: 4878cf4bc0024f3dd5193b7c6bdd5465863d4d9c2cd9baa004a94bdc735dba3e
- Baseline validation results: 8e2f305efd65c8dd7f1e089d93a5f0ab3f505e21946ef4d5065e333620b2ad4c
- Baseline summary: f5f32eb0792fbc9d2c87ec50c6b3f4beab0d894d1f9816c23632e0258920a861

## Reproduction

