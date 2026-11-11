# Issue #64 Stage 1 — parser baseline

## Recovery-adapter and category-reporting correction (latest)

This addendum records the P1/P2 runner correction on PR #63. It supersedes only the runner/recovery interpretation below; previous corpus review and semantic-decision history remain intact. The 250 fixtures, expected labels, parser, resolver, session and production behavior were unchanged.

### Recovery contract

`actual.parser_diagnostic_codes` retains the parser's raw diagnostic codes. The runner uses one `RECOVERY_ERROR_MAP` to link linguistic error categories, oracle `diagnostic_codes`, and parser diagnostic codes; `UNKNOWN_TOKEN`, social prefixes and contextual-target notes are explicitly non-recovery diagnostics. Unknown parser codes are preserved in each result and counted under `unmapped_parser_diagnostics` instead of silently becoming recoveries.

Only non-empty `parser_codes` are treated as parser evidence. Categories such as `WORD_ORDER`, `PRONOUN_CASE` and `MISSING_MODAL` currently have no parser diagnostic mapping; when such a code appears, it is surfaced as unmapped rather than treated as supported. The runner prefers a Boolean `recovery_used` or `recovery.used` emitted by the parser. If absent, the test adapter infers `recovery_used` only when the effective parser/session result is `RECOGNIZED`, a non-empty intent exists, no unknown significant token or unsupported feature/domain is present, no ambiguity/clarification reaction was returned, and at least one mapped grammatical-error diagnostic exists. The inference is labeled `INFERRED_FROM_DIAGNOSTIC`; it is benchmark instrumentation, not a production parser claim. A structured flag with an invalid type is reported as invalid. Resolver clarification and unsupported results block recovery even when the raw parse contains a grammatical diagnostic.

Diagnostic coverage is a separate measure. It compares actual mapped parser categories with the oracle's `diagnostic_codes`; it never sets `actual.recovery_used`. For individually named errors it reports `FULL`, `PARTIAL` or `MISSING`. For `MULTIPLE_RECOVERABLE_ERRORS`, one mapped parser category is only `PARTIAL`; at least two distinct mapped categories are needed for aggregate `FULL` coverage. Thus recognizing one issue cannot stand in for detecting all errors in a compound-error example. `FULL` here measures diagnostic coverage, not proof that every intended meaning was recovered.

### Recovery regression checks

The baseline runner executes 13 focused adapter checks on every run: correct input, mapped error with a recognized intent, resolver clarification, unknown significant token, unsupported multi-intent, fully and partially covered named compound errors, fully and partially covered aggregate compound errors, expected error without parser evidence, unknown parser diagnostic, and structured-flag precedence. **13 PASS / 0 FAIL.**

### Latest unchanged-parser result

The complete baseline ran twice against the unchanged production path. Both runs exited 0 and wrote byte-identical outputs. Corpus agreement remains **93/250 (37.2%)**; the new adapter changes observability and recovery accounting only, not parser behavior or semantic agreement.

| Recovery metric | Result |
|---|---:|
| Oracle `recovery_used=true` | 80 |
| Adapter `recovery_used=true` | 1 |
| True positive / false negative | 0 / 80 |
| False positive / true negative | 1 / 169 |
| Diagnostic coverage: full / partial / missing / no gold error / unexpected | 0 / 0 / 77 / 172 / 1 |
| Recovery status: blocked ambiguity / unknown / unsupported | 29 / 139 / 3 |
| Unmapped parser diagnostic occurrences | 0 |

The one false positive is `C-049: Du helfen.`: the unchanged parser reports `RECOGNIZED/REPORT_STATE` plus `AGREEMENT_MISMATCH`, although the oracle says the speech act/beneficiary is unclear. The adapter cannot safely infer that this parser result is semantically wrong without using the oracle decision as runtime evidence; the false positive is retained and exposed as a benchmark finding. This also demonstrates why `recovery_used` remains distinct from diagnostic coverage and oracle agreement. The 80 false negatives show a real capability/diagnostic gap in the unchanged parser; this Stage 1 correction does not repair it.

Decision agreement and the confusion matrix did not change: 93/250; false acceptance 28; false rejection 81; missed clarification 45; role mismatches 110 (3 reversals); polarity mismatches 130 (6 lost-negation cases); objective advancement mismatch 86.

### Group labels, oracle decisions and phenomenon families

Groups A–E describe the original fixture design focus. They are not outcome classes: A/B/C/D/E contain respectively 50/80/60/40/20 rows, while their actual oracle decisions are:

| Group | RECOGNIZED | NEEDS_CLARIFICATION | UNKNOWN | UNSUPPORTED |
|---|---:|---:|---:|---:|
| A | 50 | 0 | 0 | 0 |
| B | 69 | 5 | 0 | 6 |
| C | 6 | 47 | 0 | 7 |
| D | 0 | 2 | 20 | 18 |
| E | 16 | 4 | 0 | 0 |

The runner reports outcomes separately by actual oracle decision (141 recognized, 58 clarification, 20 unknown, 31 unsupported) and by phenomenon-derived family. Family assignment reads only the `phenomena` tags, not group or expected decision. A fixture may carry multiple phenomenon tags, so family counts are incidences (285), not a partition of the 250 utterances.

| Phenomenon family | Incidences | Oracle decisions in those rows | Parser decisions in those rows |
|---|---:|---|---|
| Grammatical error | 87 | 74 recognized, 7 clarification, 6 unsupported | 21 recognized, 10 clarification, 55 unknown, 1 unsupported |
| Semantic ambiguity | 26 | 23 clarification, 3 unsupported | 8 recognized, 8 clarification, 10 unknown |
| Unsupported multi-intent | 16 | 14 unsupported, 2 clarification | 2 recognized, 2 clarification, 10 unknown, 2 unsupported |
| Unknown/unsupported domain | 38 | 20 unknown, 18 unsupported | 2 recognized, 35 unknown, 1 unsupported |
| Context-dependent | 58 | 32 recognized, 26 clarification | 46 recognized, 4 clarification, 8 unknown |
| Other | 60 | 54 recognized, 6 clarification | 27 recognized, 3 clarification, 30 unknown |

These views let reviewers distinguish a group's sampling purpose from expected semantic behavior and compare grammar, ambiguity and system-capability boundaries directly.

### Verification and hashes

| Check | Result |
|---|---|
| Corpus count, unique IDs, split and group counts | PASS — 250 total; dev 200 and validation 50; A–E 50/80/60/40/20 |
| Baseline recovery-contract checks | PASS — 13/13 |
| Complete unchanged-parser baseline | PASS — 250 cases, exit 0; semantic mismatches remain findings |
| Deterministic repeat | PASS — dev, validation and summary SHA-256 identical across runs |
| Communication Lab regression suite | PASS — 106 PASS, 0 FAIL, exit 0 |
| Production parser/resolver/session unchanged | PASS — no production source edits |
| Runtime cleanup | FAIL diagnostic — existing Quick Audio/Cogito null-node errors and Godot resource/ObjectDB cleanup warnings; tests completed |

- Corpus dev: `f34456bd145ee7b75a37b135e2491667127266c9ba40c9be66fbf190b4ce8330`
- Corpus validation: `d2f84c8023bf276a7d474d62495882d0f22a7f9b38eefd62e51b009be1d29f90`
- Baseline dev: `ec0c0bb12d33a19184eb4a7eeab5e8dc4777b47e02bad6109a519d07d0da4f12`
- Baseline validation: `d69c2dd21620e9670839b19ce58abb9be45dc35ce20832337dc96a9d3f025122`
- Baseline summary: `02a96242dfae449e07540bc56273477f7c5b8a54805f455845a45eaf9cecd0aa`

Outputs remain ignored in `.local/issue64/`. The issue's gold labels and original group/split distribution were not changed.


## Latest targeted review (supersedes earlier metrics below)

This is the final Stage 1 review addendum for the PR-head baseline `aaf2a37d1899eaa152eecda12160078a3c0ff939` (Godot 4.7.1). The earlier audit history and hashes below are retained. This pass changes oracle annotations only; no parser, grammar, resolver, catalog, session, UI, scene or asset source changed.

### Latest verification

| Check | Result |
|---|---|
| Fixture structure and distribution | PASS — exactly 250 unique IDs; A–E 50/80/60/40/20; stratified dev 200 and validation 50 |
| Semantic role and compound-frame integrity | PASS — all OFFER_HELP roles consistently identify player helper and Astera beneficiary; each MULTIPLE_INTENTS case is UNSUPPORTED and retains at least two component frames |
| Unchanged-parser baseline | PASS — 250 cases; runner exit 0; semantic agreement remains a measured FAIL, not a test-run failure |
| Deterministic repeat | PASS — dev, validation and summary output hashes match byte-for-byte across two runs |
| Communication Lab regression suite | PASS — 106 assertions, 0 assertion failures, exit 0 |
| Production parser/session sources unchanged | PASS — no edits to production communication files |
| Runtime shutdown diagnostics | FAIL — existing shared Quick Audio/Cogito null-node errors and Godot resource/ObjectDB cleanup warnings; assertions and runner completed |

### Latest unchanged-parser metrics

Decision agreement is **93/250 (37.2%)**. Intent agreement is 52/250; full-frame agreement is 10/250. Development and validation remain separate.

| Metric | Overall | Dev (200) | Validation (50) |
|---|---:|---:|
| Decision match | 93 (37.2%) | 77 (38.5%) | 16 (32%) |
| Intent match | 52 | 44 | 8 |
| Full semantic frame match | 10 | 7 | 3 |
| False acceptance | 28 | 23 | 5 |
| False rejection | 81 | 62 | 19 |
| Missed clarification | 45 | 36 | 9 |
| Wrong clarification reason | 13 | — | — |
| Clarification without candidate output | 13 | 10 | 3 |
| Actor/recipient mismatch | 110 | — | — |
| Role reversal | 3 | — | — |
| Polarity mismatch | 130 | — | — |
| Lost negation | 6 | — | — |
| Incorrect objective advancement | 86 | 70 | 16 |
| Unknown vs unsupported confusion | 26 | — | — |
| False help offer | 6 | — | — |
| Negative help parsed as offer | 2 | — | — |

#### Decision confusion matrix

| Oracle \ Parser | RECOGNIZED | NEEDS_CLARIFICATION | UNKNOWN | UNSUPPORTED |
|---|---:|---:|---:|---:|
| RECOGNIZED | 60 | 6 | 74 | 1 |
| NEEDS_CLARIFICATION | 24 | 13 | 21 | 0 |
| UNKNOWN | 2 | 0 | 18 | 0 |
| UNSUPPORTED | 2 | 1 | 26 | 2 |

#### Representative unchanged-parser findings (15 of 25 available)

| ID | Input | Oracle | Parser | Finding |
|---|---|---|---|---|
| E-014 | `Warum?` | NEEDS_CLARIFICATION / — (—→—; unknown; question) | RECOGNIZED / WHY (player→astera; positive; question) | No prior proposition exists for Warum?; parser accepts it as WHY. |
| D-031 | `Ich bin müde und ich bin nicht müde.` | NEEDS_CLARIFICATION / — (player→—; unknown; statement) | RECOGNIZED / PLAYER_MOOD_LOW (player→astera; negative; statement) | Contradictory positive/negative mood clauses collapse to one low mood. |
| C-053 | `Müde?` | NEEDS_CLARIFICATION / — (—→—; unknown; unknown) | RECOGNIZED / PLAYER_MOOD_LOW (player→astera; positive; question) | An isolated adjective question is mapped to the player being tired. |
| B-077 | `ich nicht gut, warum du?` | NEEDS_CLARIFICATION / — (—→—; unknown; unknown) | RECOGNIZED / PLAYER_MOOD_GOOD (player→astera; positive; question) | Malformed mood plus warum du? is accepted as a positive mood statement. |
| C-009 | `Ich kann dir helfen, hilf mir.` | UNSUPPORTED / — (—→—; unknown; unknown) | NEEDS_CLARIFICATION / — (player→astera; positive; statement) | Two clear opposite-direction help acts produce clarification instead of the multi-intent boundary. |
| B-071 | `ich bin Alex und heute müde` | UNSUPPORTED / — (—→—; unknown; unknown) | UNKNOWN / — (player→astera; unresolved; unresolved) | Name plus tiredness coordination is not preserved as two frames. |
| B-073 | `ich möchte dir helfen aber du müde` | UNSUPPORTED / — (—→—; unknown; unknown) | UNKNOWN / — (player→astera; unresolved; unresolved) | Offer plus Astera mood statement is not preserved atomically. |
| C-007 | `Ich helfe dir, du mir.` | UNSUPPORTED / — (—→—; unknown; unknown) | UNKNOWN / — (player→astera; unresolved; unresolved) | Reciprocal help frames are not surfaced by the one-intent parser. |
| B-038 | `Du mir helfen.` | NEEDS_CLARIFICATION / — (astera→player; positive; unknown) | NEEDS_CLARIFICATION / — (astera→astera; positive; statement) | Speech act is clarified; current output still reports the wrong recipient and no candidates. |
| C-004 | `ich helfen du` | RECOGNIZED / OFFER_HELP (player→astera; positive; offer) | NEEDS_CLARIFICATION / — (player→astera; positive; statement) | The player subject fixes offer direction; parser still asks for clarification. |
| C-006 | `mir helfen dir` | NEEDS_CLARIFICATION / — (—→—; positive; unknown) | NEEDS_CLARIFICATION / — (unresolved→astera; positive; statement) | No subject fixes helper direction; parser still invents a recipient. |
| A-038 | `Ich kann nicht helfen.` | RECOGNIZED / PLAYER_CANNOT_HELP (player→astera; negative; statement) | RECOGNIZED / OFFER_HELP (player→astera; positive; statement) | Negated inability is misread as OFFER_HELP, losing negation and risking goal progress. |
| C-013 | `Ich kann nicht dir helfen.` | RECOGNIZED / PLAYER_CANNOT_HELP (player→astera; negative; statement) | RECOGNIZED / OFFER_HELP (player→astera; positive; statement) | Negated help is also misread as an offer. |
| B-041 | `Wie geht es du?` | RECOGNIZED / ASK_MOOD (astera→—; positive; question) | UNKNOWN / — (unresolved→astera; unresolved; unresolved) | Mood question is not recognized; expected ask_mood objective is not advanced. |
| E-011 | `Und du?` | RECOGNIZED / ASK_BACK (astera→—; positive; question) | RECOGNIZED / ASK_BACK (player→astera; positive; question) | Context resolves Und du? as Astera mood; parser does not return that reference/objective. |

### Corrections in this pass

**48 case IDs** were corrected or given explicit semantic-role/frame fields: `A-036`, `A-037`, `A-038`, `A-039`, `A-040`, `B-006`, `B-007`, `B-012`, `B-020`, `B-025`, `B-031`, `B-032`, `B-035`, `B-038`, `B-041`, `B-042`, `B-043`, `B-045`, `B-046`, `B-048`, `B-049`, `B-060`, `B-064`, `B-070`, `B-071`, `B-072`, `B-073`, `B-076`, `B-078`, `B-080`, `C-003`, `C-004`, `C-005`, `C-006`, `C-007`, `C-008`, `C-009`, `C-013`, `C-023`, `C-049`, `C-050`, `C-051`, `C-055`, `C-056`, `C-058`, `C-059`, `D-033`, `E-011`. Exact original and corrected expectations, input, case-level German justification and Stage 2 impact are recorded in the appended per-case ledger.

The chosen rule is: a single recoverable intent can be recognized; independently clear compound intents are represented by separate `intents`/`semantic_frames` but the combined submission is `UNSUPPORTED/MULTIPLE_INTENTS` until the runtime can process every frame atomically; `NEEDS_CLARIFICATION` is reserved for unresolved meaning, speech act or critical roles. In `OFFER_HELP`, the helper is always the player and the beneficiary Astera for the audited offer utterances. `grammatical_subject` and `experiencer` stay separate from `helper` and `help_recipient`.

B-038 was changed to clarify REQUEST_HELP versus DESCRIBE_HELP: `Du mir helfen.` contains no finite verb, so the issue is not agreement. Its pronouns establish Astera as helper and the player as beneficiary, but without a question marker or context the speech act is not sufficiently clear. B-012 keeps its request reading because the question marker is present; C-049 additionally lacks a stated beneficiary. B-041 and contextual E-011 consistently advance `ask_mood`.

Remaining conservative readings: C-006, C-011 and C-012 keep clarification because their forms do not establish the helping direction safely. Compound treatment is an oracle policy for Stage 2; this pass does not implement it.

### Latest hashes and reproduction

- `dev.jsonl`: `f34456bd145ee7b75a37b135e2491667127266c9ba40c9be66fbf190b4ce8330`
- `validation.jsonl`: `d2f84c8023bf276a7d474d62495882d0f22a7f9b38eefd62e51b009be1d29f90`
- Baseline dev output: `f18f6771c71633b0a3e0068bf881c5f6feb73a537f522a606dd5957073f0a723`
- Baseline validation output: `fb539ea45b318c0a6980a3893f39d27423a461c221fa8c96ef2a2d3e800e4c7a`
- Baseline summary: `45027ed7f6c026700218ace098724f0f0d1f644ebf47beebc4bb133d217f08b2`

Reproduction command (run twice for determinism):

    $env:APPDATA = Join-Path (Get-Location) '.local/godot-appdata'
    $godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
    & $godot --headless --path . --script res://implementations/communication_lab/tests/run_corpus_baseline.gd --quit-after 300
    & $godot --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd --quit-after 150

The complete machine outputs are ignored under `.local/issue64/`; they are not part of the PR.


## Previous result (historical; superseded by latest targeted review)

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

## Previous semantic baseline (historical; superseded above)

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

PowerShell:

    $env:APPDATA = Join-Path (Get-Location) '.local/godot-appdata'
    $godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
    & $godot --headless --path . --script res://implementations/communication_lab/tests/run_corpus_baseline.gd --quit-after 300
    & $godot --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd --quit-after 150

The runner writes per-case results and summary to ignored .local/issue64/. Two baseline executions were compared through their SHA-256 hashes.

The regression suite logs existing shared Cogito/Quick Audio errors (Audio.gd attempts add_child on null; CogitoPlayerSimple.slide_audio_init calls reparent on null) and Godot resource/ObjectDB cleanup warnings. Assertions still completed with zero failures; shared addons were not changed.

## Audit notes and limits

- The exact issue examples and all requested analogous clusters were reviewed, including verb agreement, case errors, missing forms, negation, slow speech vs repeat, multi-clause utterances, Ja/Nein, Und du?, Warum?, and all ten E context pairs.
- The audit separates recognized lexical content, unknown content words, unsupported conversation domains/constructions, recoverable errors, missing context, semantic role ambiguity, contradiction, and multi-intent composition.
- The ledger documents 217 cases with expected-label changes; 11 same-group/split input replacements are itemized separately and may overlap those label corrections.
- Some pragmatic judgments remain reviewable rather than universal, especially fragmentary forms (Langsamer, bitte; Hilfe anbieten?) and isolated Ja/Nein. Each case remains conservative, with candidate meanings recorded in the oracle.
- No parser code was changed; no Stage 2 / Issue #65 work was started; no inference server was started/restarted; no PR was merged.



## Final Stage 1 recovery-contract correction (2026-11-12)

This section supersedes earlier recovery-contract wording and metrics in this document. The parser/resolver/session are unchanged. The corrected gold contract treats `recovery_used` as true only when a grammatical correction was actually used and the complete intended meaning was recovered; the runner reports grammatical-error detection and semantic completeness separately. Complete clause frames can be reported for unsupported multi-intent utterances. Unresolved meaning such as B-038 is partial and cannot set `recovery_used`.

### Gold changes

- B-007, B-060, B-073, B-076 and B-080 retain `recovery_used: true`, now explicitly declare `semantic_recovery_status: COMPLETE`, and give every semantic frame positive polarity. Their complete frames recover each clause's intent, grammatical subject, actor, recipient, polarity and speech act (plus help roles or experiencer where applicable); the overall decision remains `UNSUPPORTED/MULTIPLE_INTENTS` because the one-intent runtime cannot safely execute both acts.
- B-038 changes `recovery_used: true` to `false` and records `semantic_recovery_status: PARTIAL`: Astera/helper and player/beneficiary are clear, but REQUEST_HELP versus DESCRIBE_HELP remains unresolved. Its `MISSING_FINITE_VERB` diagnostic remains grammatical-error evidence.
- Expected grammatical diagnostics total 80; the expected complete grammatical recoveries total 79. The difference is B-038. This separates error existence from semantic recovery without changing other gold labels.

### Diagnostic category integrity

`REDUNDANT_INFINITIVE` (B-004), `MISSING_OBJECT` (B-036) and `LEXICAL_CALQUE` (B-068) are registered grammatical categories with explicit empty `parser_codes`. Their expected labels remain intact, so their parser coverage is `MISSING`, not `NO_GOLD_ERROR_EXPECTED`. Ambiguity, unknown vocabulary and unsupported-feature diagnostics are explicitly classified separately. Any unclassified oracle diagnostic is listed as `UNCLASSIFIED_ORACLE_DIAGNOSTICS` and causes structural validation to fail.

### Unchanged-parser baseline

- Cases: 250; split/group distribution: dev 200 (A40/B64/C48/D32/E16), validation 50 (A10/B16/C12/D8/E4).
- Decision agreement: 93/250 (37.2%); false acceptances 28; false rejections 81; missed clarifications 45; role swaps 3; lost-negation cases 6. These are parser baseline findings, not improvements. Production parser behavior was not changed.
- Recovery diagnostics: expected grammatical error 80; actual mapped grammatical-error detection 1; expected complete recovery 79; actual complete `recovery_used` 0. Diagnostic coverage: MISSING 80, NO_GOLD_ERROR_EXPECTED 169, UNEXPECTED_DETECTION 1. Semantic parser output: PARTIAL 247, NONE 3. The parser exposes no complete multi-frame representation in these baseline results.
- Baseline runner passed twice with identical result hashes; Communication Lab regression suite: 106 PASS, 0 assertion failures (Godot emits existing addon null-node and resource/ObjectDB cleanup errors/warnings at exit).

### Current SHA-256

- `dev.jsonl`: `9a004125f84c9e51f22dc98725e4f2e8ae1f5403b70fb2dcd4f5d592f6ea2044`
- `validation.jsonl`: `4f4154f86cae665d2f6bdff73bd5ef7dc76238565804be1ad6dd8999d14a2fd1`
- baseline dev results: `8fd22629fe15f86725ab508803882ea3b96f06e828e8888d081fe4ecf9f7a382`
- baseline validation results: `359ca9cb7674bf03fa267717ff5a1b5749515ebf5c0d55c15679c21b91d48432`
- baseline summary: `7a0b0cc0abd76d2104f6eba584d6cea1fbc0413c9f24a9f2da824b1413a45242`

The full result JSONL and summary are generated under ignored `.local/issue64/` and are not committed. Reproduction commands above remain valid.

