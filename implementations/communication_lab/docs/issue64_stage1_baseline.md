# Issue #64 Stage 1 — parser baseline

## Result

**Runner/integrity: PASS. Semantic baseline: FAIL by design.** The frozen 250-case corpus is a measurement fixture; the parser was not changed to make the cases pass.

| Check | Result |
| --- | --- |
| Unique case IDs and JSONL shape | PASS — 250 |
| Group counts A–E | PASS — 50 / 80 / 60 / 40 / 20 |
| Stratified dev / validation | PASS — 200 / 50 with 40/64/48/32/16 and 10/16/12/8/4 |
| Baseline runner | PASS — completed all cases, exit 0 |
| Repeatability | PASS — two runs produced identical result and summary SHA-256 hashes |
| Existing Communication Lab regression suite | PASS — 97 assertions, 0 assertion failures, exit 0 |
| Parser/session implementation unchanged | PASS |

The regression run still prints two existing Cogito/Quick Audio script errors (Audio.gd calls add_child on a null value; CogitoPlayerSimple.slide_audio_init calls reparent on a null value), plus resource cleanup warnings. They did not fail the 97 assertions, but remain visible and are not attributed to this corpus task.

## Baseline environment and reproduction

- Baseline revision: d3ce22a (Add keyboard switching between composer fields).
- Godot: 4.7.1 stable official, build a13da4feb.
- Runner: implementations/communication_lab/tests/run_corpus_baseline.gd.
- Oracle rules: [issue64_oracle.md](issue64_oracle.md).
- Parser inputs: dialogue_resolver.gd, then parser.gd fallback exactly as selected by LabSession.submit; session resolution and objective updates use the unchanged lab_session.gd helpers. The runner uses a fresh context per case and does not write the persistent attempt journal.
- Frozen fixture SHA-256: dev.jsonl `0766bf8f5603bc4ee531801525073b1ad7483744f57c879e1d4ffdeee051dc52`; validation.jsonl `f2606448aebbffa5b21065395754ff396c7387d5a4612c5423ef5d7f9852f999`.
- Captured result SHA-256: dev JSONL `cd3f2adcbff12f6c26086fbd5159894d879a329f9ce7c29093cddf3bf6be6b67`; validation JSONL `a507fed197c3cc8c5aa04f854c32abcc06f27db0a38ad5e5875eb896bdd4cc1e`; summary `66fd99c080030f7b3e66918c05b24e7803255d9e520e1020a763a6e41f8f20ea`.

Reproduction in PowerShell:

    $env:APPDATA = Join-Path (Get-Location) '.local/godot-appdata'
    $godot = (Get-Command Godot_v4.7.1-stable_win64_console.exe).Source
    & $godot --headless --path . --script res://implementations/communication_lab/tests/run_corpus_baseline.gd --quit-after 300

The command writes full per-case results and the aggregate JSON summary under ignored .local/issue64/. Run it twice to check determinism. Regression tests are separate:

    & $godot --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd --quit-after 120

## Decision metrics

decision_match compares the oracle decision with the parser status. It does not mean the whole semantic frame matches.

| Group | Cases | Exact decision | Decision rate |
| --- | ---: | ---: | ---: |
| A — correct expressions | 50 | 25 | 50% |
| B — recoverable learner errors | 80 | 24 | 30% |
| C — ambiguous meanings | 60 | 13 | 22% |
| D — unknown / unsupported | 40 | 19 | 48% |
| E — context-dependent | 20 | 19 | 95% |
| **Overall** | **250** | **100** | **40%** |

### Decision confusion matrix

Rows are oracle decisions; columns are current parser/session decisions.

| Expected ↓ / Actual → | Recognized | Needs clarification | Unknown | Unsupported |
| --- | ---: | ---: | ---: | ---: |
| Recognized | 66 | 4 | 76 | 1 |
| Needs clarification | 23 | 15 | 24 | 1 |
| Unknown | 2 | 0 | 18 | 0 |
| Unsupported | 1 | 1 | 18 | 1 |

Across all cases there were **26 false acceptances** (oracle was not recognized, current parser recognized), **81 false rejections** (oracle was recognized, parser did not), and **48 missed clarifications**. For clarification cases already classified as such, 15 returned the wrong or missing reason. Unknown and unsupported were confused in 18 cases.

## Results by intended meaning

Decision is the number whose status matched among that oracle intent. Intent is exact intent matches; the observed column records status counts, so a correct status with the wrong intent remains visible.

| Oracle intent | Cases | Decision matches | Intent matches | Observed parser statuses |
| --- | ---: | ---: | ---: | --- |
| ACCEPT_HELP | 2 | 2 | 2 | 2 recognized |
| ACCEPT_SLOW | 1 | 1 | 1 | 1 recognized |
| ASK_ACTIVITY | 14 | 5 | 5 | 5 recognized, 9 unknown |
| ASK_ASTERA_MOOD | 2 | 1 | 0 | 1 recognized, 1 unknown |
| ASK_BACK | 4 | 3 | 2 | 3 recognized, 1 unknown |
| ASK_MOOD | 10 | 3 | 3 | 3 recognized, 6 unknown, 1 unsupported |
| ASTERA_MOOD_LOW | 1 | 1 | 0 | 1 recognized with wrong intent |
| DECLINE_HELP | 2 | 2 | 2 | 2 recognized |
| DECLINE_SLOW | 2 | 1 | 1 | 1 recognized, 1 unknown |
| FAREWELL | 10 | 3 | 3 | 3 recognized, 7 unknown |
| GREETING | 7 | 4 | 4 | 4 recognized, 3 unknown |
| OFFER_HELP | 19 | 8 | 7 | 8 recognized, 2 clarification, 9 unknown |
| PLAYER_CANNOT_HELP | 1 | 1 | 0 | 1 recognized with wrong intent |
| PLAYER_MOOD_GOOD | 9 | 5 | 5 | 5 recognized, 4 unknown |
| PLAYER_MOOD_LOW | 15 | 10 | 8 | 10 recognized, 5 unknown |
| PLAYER_NAME | 11 | 4 | 4 | 4 recognized, 7 unknown |
| PLAYER_PLAN | 14 | 7 | 7 | 7 recognized, 7 unknown |
| REPORT_NONUNDERSTANDING | 2 | 0 | 0 | 1 clarification, 1 unknown |
| REQUEST_HELP | 4 | 2 | 0 | 2 recognized as another intent, 1 clarification, 1 unknown |
| REQUEST_REPEAT | 14 | 1 | 1 | 1 recognized, 13 unknown |
| THANKS | 1 | 0 | 0 | 1 unknown |
| WHY | 2 | 2 | 2 | 2 recognized |

Clarification, unknown and unsupported cases have no single oracle intent; their status breakdown is in the confusion matrix.

## Results by learner-error category

| Group B phenomenon | Cases | Exact decision |
| --- | ---: | ---: |
| Verb agreement | 11 | 6 |
| Infinitive instead of finite verb | 10 | 0 |
| Word order | 10 | 6 |
| Missing modal | 9 | 1 |
| Pronoun case | 10 | 2 |
| Omitted subject or verb | 10 | 2 |
| Typo / near form | 10 | 2 |
| Multiple recoverable errors | 10 | 5 |

The unknown-word subset had 18/20 exact decisions. The unsupported conversational/domain subset had 1/20 exact decisions; long-chain handling matched 1/1. See the JSONL outputs for the per-phenomenon and per-case comparison.

## Critical findings and representative cases

The table contains 20 representative baseline cases, including both user examples. Replies and objective effects are from the unchanged session resolver.

| ID | Input | Expected → actual | NPC reply / observed effect |
| --- | --- | --- | --- |
| A-021 | Mir geht es nicht gut. | PLAYER_MOOD_LOW → PLAYER_MOOD_GOOD | “Oh, schön!”; mood objective advanced. Negation was lost. |
| A-038 | Ich kann nicht helfen. | PLAYER_CANNOT_HELP → OFFER_HELP | “Oh! Danke! Das ist nett!”; offer-help objective advanced. |
| A-013 | Wie geht es Ihnen? | recognized ASK_MOOD → unknown | “Ich verstehe nicht.” |
| B-012 | Du mir helfen? | REQUEST_HELP → needs clarification | “Was meinst du?”; does not infer the likely request. |
| B-024 | Ich nicht verstehe. | recognized non-understanding → needs clarification | “Was meinst du?” |
| B-031 | ich dir helfen | recognized OFFER_HELP → needs clarification | “Was meinst du?”; misses the oracle's clear help direction. |
| B-043 | Du kann mir helfen? | REQUEST_HELP → OFFER_HELP | “Oh! Danke!”; role direction reverses and objective advances. |
| B-061 | Hallo Astera, wie get es dir? | recognized ASK_MOOD → unsupported | “Ich verstehe nicht.” |
| B-064 | Kann ich dir helfn? | recognized OFFER_HELP → unknown | “Ich verstehe nicht.” |
| B-015 | Ich Deutsch lernen. | recognized PLAYER_PLAN → unknown | “Ich verstehe nicht.” |
| B-066 | Was machts du? | recognized ASK_ACTIVITY → unknown | “Ich verstehe nicht.” |
| B-069 | Bis spater! | recognized FAREWELL → unknown | “Ich verstehe nicht.” |
| B-070 | Ich kann dir helfe. | recognized OFFER_HELP → unknown | “Ich verstehe nicht.” |
| C-001 | Dir helfen? | clarify roles → clarification without oracle reason | “Was meinst du?”; safe stop, but no specific diagnostic. |
| C-002 | Ich mochtest helfe du | clarify as AMBIGUOUS_ROLES → unknown | “Ich verstehe nicht.”; no useful clarification. |
| C-031 | Und du? without a prior topic | needs clarification → recognized ASK_BACK | “Was möchtest du wissen?”; selected an intent despite missing reference. |
| C-053 | Müde? with no subject/context | needs clarification → recognized PLAYER_MOOD_LOW | “Oh… warum?”; share-self objective advanced. |
| C-055 | Hallo, tschüss. | clarify competing intents → unsupported | “Ich verstehe nicht.” |
| D-024 | Was ist dein Lieblingsessen? | unsupported topic → unknown | “Ich verstehe nicht.” |
| E-001 / E-002 | Ja. with help pending / no pending question | accept help / clarify → accept help / clarify | Correct context split; the unprompted “Ja” did not advance an objective. |

Across recognized results, the baseline recorded **2 role swaps**, **2 polarity mismatches / lost negations**, and **6 false offer-help acceptances**. One of those false offers was the explicit negative Ich kann nicht helfen. The unsafe offer-help objective advance is visible in A-038 and B-043.

## Boundaries

- No parser, catalog, session, UI, animation or inference changes were made. Stage 2 / Issue #65 has not started.
- Godot GUI and visual behavior were not part of this data-only Stage 1 run.
- Full per-case outputs are ignored local artifacts; the corpus, oracle, runner and this aggregate report are committed.
- This validation set is committed and visible, not cryptographically blind. Treat it as deferred process validation, not a hidden test.
