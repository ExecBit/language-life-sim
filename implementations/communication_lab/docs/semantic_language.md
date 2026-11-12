# Productive language in the RPG runtime

The active path is `Composer → LabSession.submit → DialogueLanguage.analyze_rpg → SemanticParser.analyze → DialogueGraph.resolve`. The older social `DialogueLanguage.analyze` and `dialogue_resolver.gd` are historical code; they are not alternate recognizers for this RPG. Instructional `constructions` are displayed in F1, never matched as executable utterances.

## Meaning before execution

The parser reads word-level `syntax` from the scenario vocabulary. It combines participant/case information, predicate family, modality, negation, entity type and discourse referents. Domain `language.bindings` map a frame to a semantic action; the graph independently checks the actual node, required frame and guards. Menu choices cannot supply a missing assertion or override explicit roles/negation. An unambiguous utterance without a selected menu hypothesis can use its real edge; a conflicting selected goal requires confirmation.

An explicit missing article or copula does not require a new phrase entry. A missing object is different: the parser filters the current node's declared referents by adjective/entity compatibility. A unique candidate produces an NPC confirmation, several candidates produce a choice, and no candidate produces a request to rephrase. For example, `Ich möchte vorläufigen` at the registration node proposes `Einen vorläufigen Pass?`. This does not issue a pass. An immediate `Ja` applies the previously validated request edge and reaches the authored name-confirmation node.

Each transient interpretation stores the source node, turn, candidate frame and parser evidence. It expires after new content, rejection, scene closure or an edge. Before confirmation, the session checks the node, immediate turn and current guard again. A noun can complete an immediate object choice; `Ja` cannot choose an object. Unknown or unsupported material cannot execute a recognized prefix. History/JSONL keep original and resolved frames and the source of a confirmed meaning. F2 reads those runtime events, not a second graph.

`COMPLETE` means that the chosen supported construction has its semantic arguments. It does not certify grammatical German or unrestricted comprehension. Repairs, agreement/missing-verb diagnostics, explicit lexical evidence and contextual fields remain separate. Unbound meanings (for example another person's role) do not acquire an unrelated authored action.

## Adding vocabulary or another situation

An ordinary word addition requires data and checks, not a new branch in the parser:

1. Add every usable surface form, Russian translation and `syntax` to `vocabulary`. F1 and completion immediately use that same catalog. Do not add a complete utterance as a recognition rule.
2. Give nouns an entity ID/type, gender and display/accusative label; give adjectives compatible entity types and accusative forms. Verb forms declare a predicate family, finite/infinitive form and person. Modal forms declare the operator. New forms of an existing meaning use the existing features.
3. Reuse a domain binding for an existing type/action. A new domain action needs a declarative binding and an authored graph edge with its required frame, guards and effects. New nodes declare `language_context.referents`, topic, recipient, name slot or challenged proposition when relevant. Initial facts and system-event mappings also come from graph data.
4. Put player-action words in that action's `vocabulary`/`search_words`, and optional teaching sentences in `constructions`. Keep full sentences below words in F1. Run the contract, vocabulary, semantic, extension and route checks below.

Example of a new word of an existing type:

```json
{
  "surface": "Ausweis", "translation": "удостоверение", "pos": "noun",
  "syntax": {
    "kind": "entity", "entity_type": "access_document", "entity_id": "pass",
    "gender": "m", "label": "Ausweis", "accusative": "Ausweis"
  }
}
```

`Ich möchte einen Ausweis` then uses the existing acquisition grammar and document binding. No special-case sentence is added. The engine does not infer the meaning of an arbitrary new spelling: the author or coding agent must supply its semantic metadata. Merely appending an untranslated string cannot teach a meaning.

`tests/fixtures/language_extension.json` demonstrates a different situation: a medic, a bandage and a swab, a compatible “sterile” adjective, a new acquisition binding and two graph nodes with their own fact/effect. `test_language_extension.gd` injects this data through the same production Language/Session/Graph classes. It verifies an existing-type synonym, new-role isolation, three new requests, polarity/actor/possession contrasts, multi-object clarification, noun selection, unique-object confirmation and no dropped extra meaning. Production code never reads this fixture.

A new kind of action, complex clause or relationship outside the supported families still needs grammar work and independent contrasts. Vocabulary expansion within an existing family does not promise automatic understanding of every sentence containing those words. This is a deterministic bounded parser, not a general German conversational model.

## Error families and contrasts

The investigation baseline and confirmed old branches are documented in [parser_architecture_audit.md](parser_architecture_audit.md). Counterexamples were added before the replacement was connected. Additional contrast batches caught coverage/recovery defects during implementation.

| Family / observed root cause | General mechanism and scope | Contrasts and remaining risk |
| --- | --- | --- |
| Requests became possession because the old object/`habe` branch ran first | Build predicate/operator meaning before domain binding; do not assert facts from questions | `Ich habe keinen Pass` / `Ich möchte keinen Pass`; `Kann ich einen Pass bekommen?` / `Ich habe einen Pass`. New predicate families still need declarations. |
| Missing noun was UNKNOWN despite a compatible current referent | Typed discourse referents, adjective constraints, candidate confirmation and object choice | Full temporary-pass request / missing noun; one sterile object / two sterile objects in the extension. No automatic success merely because one edge exists. |
| Embedded `nein` was ignored by role recognition; bare refusal had no target | Proposed self-repair with confirmation; short answers bind to a concrete proposition or declared current challenge | Positive role / `kein`; `Techniker nein` / explicit denial; unbound `Ja` / name confirmation. Multiple negations require rephrasing. |
| Helper/recipient and negative ability were flattened | Pronoun case/participant roles and explicit polarity/modality | `Kann ich dir helfen?` / `Kannst du mir helfen?`; each subject with/without `nicht` and with statement/question punctuation. Negative questions may need pragmatic confirmation. |
| A known word was silently dropped after a recognizable head | Account for content, incompatible entities/topics, extra roles, prepositions and future scope; never execute part of a compound | Role plus document / role alone; role today versus unsupported future qualifier; noun choice / noun plus recipient or negation. Not a complete German attachment grammar. |
| Questions, wishes and obligations became facts/promises | Keep speech act and mode in bindings; distinguish delivery commitment from ability/obligation | `Ich bin Techniker` / `Bin ich Techniker?`; actual newcomer / desired role; delivery promise / obligation. Complex modal scopes remain outside this subset. |
| Delayed yes could refer to an old inferred request | Source-node/turn lifetime, guard recheck, cancellation and stored provenance | Immediate yes / new utterance then yes; closing / continuing; repeated terminal yes causes no duplicate effect. |
| Free-name shortcut consumed unrelated meaning | A declared name slot plus one name, permitted construction, explicit participant and no extra time/modality/question | `Ich bin Alex` / `Heiße ich Alex?`; introduction / introduction plus future or another person. Unknown names outside this slot remain unknown. |

## Source verification

Use the installed Godot **console** binary, redirecting logs to ignored `.local/`. No export is involved. Set `APPDATA` to `.local/godot-appdata` if needed for the sandbox. Run:

```powershell
$tests = @('test_language_contract','test_semantic_language','test_language_extension','test_productive_intents','test_issue68','test_vocabulary_sync','test_lab','test_semantic_scene')
foreach ($test in $tests) {
    & $engine --headless --path . --script "res://implementations/communication_lab/tests/$test.gd" --quit-after 600
}
& $engine --path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/test_semantic_scene.gd --quit-after 600
& $engine --path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/capture_issue68_graph.gd --quit-after 600
```

Observed implementation checks:

- Before replacement: **32 failures / 58 assertions** in the initial semantic regression suite against the actual Session/Language path.
- After replacement and additional contrasts: **0 failures / 94 assertions** in `test_semantic_language`; **0 failures / 19 assertions** in the data-only extension suite. These are targeted development checks, not an unbiased accuracy estimate. Additional tests separately check structural data, runtime scene, route and vocabulary contracts.
- All eight Issue #68 acceptance routes pass, including reopening without duplicate effects. The old system-event resolver's `reopen`/`REOPEN_DIALOG` mismatch was fixed through an explicit data mapping.
- Actual Composer/F1 use **249 words / 265 memo entries**, with the same translations and coverage of player-action words and generated clarification vocabulary.
- Source scene exercises the real Composer signal, contextual NPC clarification, confirmation, official result, history and all 61 native F2 connections. Opening the hidden inspector now recenters after its actual canvas size settles. Rendered clarification and F2 screenshots were visually inspected.

The old social corpus runner and `test_issue65.gd` still address removed Session objective fields; they are historical and are not an evaluation of this runtime. Their known failures were not hidden by changing gold labels. The 50 deferred-validation cases were not rerun or tuned to; no 200/50 corpus accuracy claim is made here. New domain coverage must be tested through the actual RPG entry point.

Known shared Cogito/quick_audio null-node errors and resource-cleanup warnings remain visible in source logs. They were not suppressed by modifying shared addons. Rendering with Compatibility also reports unsupported volumetric fog. These limitations are separate from the passing lab assertions. EXE/PCK/export templates were not used.
