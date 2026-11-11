# Issue #64 Stage 1 — corpus oracle

The fixture is a frozen, human-authored benchmark for the existing conversation domain. It records an interpretation before comparing against the current code. It is not a claim that every intended interpretation is already supported by the lab.

## Decisions

- `RECOGNIZED`: one defensible conversational meaning can be recovered. Grammar errors may be recoverable; a keyword match alone is insufficient.
- `NEEDS_CLARIFICATION`: more than one meaning remains plausible. The case names a reason and lists candidate interpretations. Its expected objective advance is false.
- `UNKNOWN`: a meaning-bearing token is outside the vocabulary. `unknown_tokens` names it.
- `UNSUPPORTED`: the utterance is outside the lab's supported conversation domain or combines clauses the lab cannot safely handle. `unsupported_domain` identifies the boundary.

## Semantic fields

- `actor` is the participant performing the described action/state, not automatically the player who typed the sentence. Overt pronouns retain their role when the verb form is wrong: in `Du bin müde`, `du` still refers to Astera. For example, `Du mir helfen?` describes Astera as helper; `ich dir helfen` describes the player as helper. Questions about Astera’s mood/activity assign Astera as the queried experiencer.
- `recipient` is the content-level beneficiary/recipient when one is expressed. It stays empty when the clause has no such role; a question’s addressee is not automatically its semantic recipient. For example, a help request to Astera has actor `astera`, recipient `player`, while an offer has actor `player`, recipient `astera`. Role ambiguity leaves both fields empty.
- `polarity` records grammatical polarity. `Ich kann nicht helfen` is negative and cannot be normalized to an offer.
- `speech_act` describes the intended social move (offer, request, question, statement, farewell), not punctuation alone.
- `recovery_used` is true only for a recoverable learner-form error. `diagnostic_codes` records the oracle's expected error/clarification category; parser output is retained separately and compared directly.
- `expected_objectives` names the exact conversation goals that the meaning can advance in this test context; `may_advance_objective` is its compatibility boolean and must agree with whether the list is empty. An accepted parser intent is not itself proof that an objective advanced safely. Ambiguous, unknown, unsupported, or negated-help cases cannot advance the offer-help objective.
- A phrase with two individually clear clauses is not automatically ambiguous. If the constrained one-intent lab cannot compose the clauses safely, it is labeled as an unsupported multi-intent construction; clarification is reserved for meanings that are genuinely unresolved.
- `candidate_interpretations` contains only semantically plausible meanings supported by the words/context. The unchanged parser currently exposes no candidate list; the baseline records that as an unsupported parser feature and does not score an empty list as a correct clarification.

The baseline adapter follows the same unchanged branch selection as `LabSession.submit`: first `DialogueGrammar.parse`, then the legacy `Parser.parse` fallback when the extension returns an empty dictionary. It calls the unchanged session resolver and objective helper on a per-case context. It does not append to the player's persistent attempt journal. The raw parse, NPC answer/reaction/animation, effects and resulting context are captured for inspection.

## Corpus layout

| Group | Cases | Dev | Validation | Purpose |
| --- | ---: | ---: | ---: | --- |
| A | 50 | 40 | 10 | Clear, grammatical expressions across greetings, names, mood, activity, plans, help, repeat requests and farewells |
| B | 80 | 64 | 16 | Understandable learner errors: agreement, missing finite/modal forms, word order, pronouns, omissions and typos |
