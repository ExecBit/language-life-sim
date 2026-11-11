# Issue #64 Stage 1 — corpus oracle

The fixture is a frozen, human-authored benchmark for the existing conversation domain. It records an interpretation before comparing against the current code. It is not a claim that every intended interpretation is already supported by the lab.

## Decisions

- `RECOGNIZED`: one defensible conversational meaning can be recovered. Grammar errors may be recoverable; a keyword match alone is insufficient.
- `NEEDS_CLARIFICATION`: more than one meaning remains plausible. The case names a reason and lists candidate interpretations. Its expected objective advance is false.
- `UNKNOWN`: a meaning-bearing token is outside the vocabulary. `unknown_tokens` names it.
- `UNSUPPORTED`: the utterance is outside the lab's supported conversation domain or combines clauses the lab cannot safely handle. `unsupported_domain` identifies the boundary.

## Semantic fields

- `actor` is the participant performing the described action or state. For example, a request `Du mir helfen?` describes Astera as the helper; `ich dir helfen` describes the player as helper.
- `recipient` is the participant receiving the action when one is expressed. Role ambiguity leaves both fields empty.
- `polarity` records grammatical polarity. `Ich kann nicht helfen` is negative and cannot be normalized to an offer.
- `speech_act` describes the intended social move (offer, request, question, statement, farewell), not punctuation alone.
- `recovery_used` is true only for a recoverable learner-form error. `diagnostic_codes` records the oracle's expected error/clarification category; parser output is retained separately and compared directly.
- `may_advance_objective` describes whether the recognized meaning could validly advance the current conversation objective. Ambiguous, unknown, unsupported, or negated-help cases cannot advance the offer-help objective.

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

High-risk probes include the exact user phrases `ich dir helfen` and `Ich mochtest helfe du`, the negation contrast `Ich kann helfen` / `Ich kann nicht helfen`, the reverse-role request `Du mir helfen?`, and `Ja` / `Nein` with and without pending questions. Conflicting or incomplete role forms remain clarification cases; no object, door, key, or quest action is part of this corpus.
