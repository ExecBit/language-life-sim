# Issue #64 Stage 1 — corpus oracle

The fixture is a frozen, human-authored benchmark for the existing conversation domain. It records an interpretation before comparing against the current code. It is not a claim that every intended interpretation is already supported by the lab.

## Decisions

- `RECOGNIZED`: one defensible conversational meaning can be recovered. Grammar errors may be recoverable; a keyword match alone is insufficient.
- `NEEDS_CLARIFICATION`: more than one meaning remains plausible. The case names a reason and lists candidate interpretations. Its expected objective advance is false.
- `UNKNOWN`: a meaning-bearing token is outside the vocabulary. `unknown_tokens` names it.
- `UNSUPPORTED`: the utterance is outside the lab's supported conversation domain or combines clauses the lab cannot safely handle. `unsupported_domain` identifies the boundary.

## Semantic fields

The oracle separates surface grammar from the people involved in the event:

- `grammatical_subject` is the overt syntactic subject after safe normalization; it can differ from who implicitly performs an offer.
- `experiencer` is the person whose need, feeling, or state the clause describes. In `Brauchst du Hilfe?`, Astera (`du`) is both grammatical subject and need experiencer.
- For help frames, `helper` is the person who would provide help and `help_recipient` is the beneficiary. These meanings do not change with sentence form: in `Kann ich dir helfen?`, `Brauchst du Hilfe?`, and `Ich helfe dir gern.`, the player is helper and Astera is beneficiary. The second sentence has Astera as subject/experiencer, not helper.
- `actor` names the performer of an action (or the person characterized by a non-help state); `recipient` names an expressed or contextually clear beneficiary. For requests such as `Du mir helfen?`, Astera is helper/actor and the player is recipient. A query's addressee is not automatically its recipient.
- `speech_act` is the social move, independently labeled from grammatical subject and punctuation: offer, request, question, statement, or farewell. A question about needing help can be an OFFER_HELP speech act.
- For genuinely compound inputs, `semantic_frames` preserves one compact frame per independently understandable clause. The top-level single `intent` remains empty; `intents` lists the component acts.

### Compound and ambiguity policy

The runtime currently processes one intent per submitted message and has no atomic multi-frame response/objective update. Therefore:

1. A **single recoverable intent** remains `RECOGNIZED` when learner grammar is wrong but meaning, roles, and speech act are sufficiently clear.
2. **Multiple compatible, independently clear intents** remain separate in `intents` and `semantic_frames`, but the combined utterance is `UNSUPPORTED` with `unsupported_features: ["MULTIPLE_INTENTS"]`. This is a documented capability boundary: accepting only one clause could lose meaning or advance an unrelated objective. It is not a request for clarification and not a Stage 1 parser change.
3. **Genuine ambiguity** is `NEEDS_CLARIFICATION` only if the intended speech act, semantic direction, or a critical participant role is unresolved. Two clauses alone do not justify ambiguity; both can be represented as frames when each is clear.
4. A long chain can include `LONG_CHAIN` as an additional unsupported feature while preserving any clearly recoverable component frames. Stage 2 may propose support, but must handle all frames atomically before acceptance.

For example, `Ich kann dir helfen, hilf mir.` and `Ich helfe dir, hilf mir.` both clearly combine player-offer and Astera-request acts. Both are `UNSUPPORTED/MULTIPLE_INTENTS` in this one-intent runtime, with the same two component frames. By contrast, `Du helfen.` makes Astera the helper but omits a beneficiary and finite verb, so REQUEST_HELP versus DESCRIBE_HELP remains a speech-act clarification.

`polarity` records grammatical polarity; `Ich kann nicht helfen` is negative and cannot become an offer. `recovery_used` refers to a recoverable learner-form error even where an otherwise clear compound is unsupported by runtime capability. `diagnostic_codes` records the linguistic error or clarification category; `unsupported_features` records system capability boundaries.

`expected_objectives` lists the exact goals a single recognized meaning can advance in this test context. It must agree with `may_advance_objective`; unsupported, ambiguous, unknown, or negated-help messages cannot advance an objective. Recognized `ASK_MOOD` and contextual `ASK_BACK` with topic `player_mood` advance `ask_mood`.

`candidate_interpretations` contains only plausible meanings supported by the words/context. The unchanged parser currently exposes no candidate list; the baseline records that as an unsupported parser feature and does not score an empty list as a correct clarification.
The baseline adapter follows the same unchanged branch selection as `LabSession.submit`: first `DialogueGrammar.parse`, then the legacy `Parser.parse` fallback when the extension returns an empty dictionary. It calls the unchanged session resolver and objective helper on a per-case context. It does not append to the player's persistent attempt journal. The raw parse, NPC answer/reaction/animation, effects and resulting context are captured for inspection.

## Corpus layout

| Group | Cases | Dev | Validation | Purpose |
| --- | ---: | ---: | ---: | --- |
| A | 50 | 40 | 10 | Clear, grammatical expressions across greetings, names, mood, activity, plans, help, repeat requests and farewells |
| B | 80 | 64 | 16 | Understandable learner errors: agreement, missing finite/modal forms, word order, pronouns, omissions and typos |
| C | 60 | 48 | 12 | Unresolved roles, polarity, omitted subjects, context-dependent fragments and competing intents |
| D | 40 | 32 | 8 | Unknown lexical items and unsupported conversational structures/topics |
| E | 20 | 16 | 4 | Same utterance under contrasting pending questions and conversation/NPC state |
| **Total** | **250** | **200** | **50** | Stratified 80/20 development and deferred validation |

The E cases use ten paired prompts. Four pairs cross the dev/validation boundary; the other six stay together in dev. This is process separation, not a blind benchmark: the validation fixture is committed and visible.

## Audit and review

Every fixture was checked against German grammar, error type, semantic roles, polarity, speech act, recoverability, supplied context, clarification need and goal progression. The audit corrected recurring errors in role attribution, negation, speech acts, multi-clause flattening, contextual fragments, and candidate lists. Exact before/after labels and a linguistic justification are in [issue64_gold_review_ledger.md](issue64_gold_review_ledger.md). The gold changes require user review; recording them here does not imply acceptance.

High-risk probes include the exact user phrases `ich dir helfen` and `Ich mochtest helfe du`, the negation contrast `Ich kann helfen` / `Ich kann nicht helfen`, the reverse-role request `Du mir helfen?`, and `Ja` / `Nein` with and without pending questions. Conflicting or incomplete role forms remain clarification cases; no object, door, key, or quest action is part of this corpus.


## Targeted review addendum (latest Issue #64 review)

The current correction pass applies the compound policy consistently to clear coordinated/juxtaposed acts and separates Astera’s need/experiencer role from the implied player helper in “Brauchst du Hilfe?”. Full case-level before/after details are appended to the review ledger; previous audit history is retained. No production parsing logic changes are part of this Stage 1 update.
