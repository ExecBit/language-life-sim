# Issue #64 Stage 1 — parser baseline


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


