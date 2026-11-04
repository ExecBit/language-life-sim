# Language Life Sim

A small Godot 4 learning-game prototype. The goal is to test whether **10–15 everyday German lemmas** can be learned and revisited through different playable situations, before expanding toward a 4,000-word curriculum. The current starter list is Goethe-A1-derived, not frequency-ranked.

## Current status

**LEX-01 is playable.** `scenes/main.tscn` is the learning room: a Mage and a Knight give short German sentences, and the player answers by clicking objects in the room, by carrying an object to a target, or by choosing a spoken answer. Progress per lemma is tracked and some situations repeat a lemma one simulated day later in a changed context.

All content lives in JSON. Adding a learning situation means adding or editing a scenario record - no gameplay script, no new asset, no new test file.

What is in place now:

- **Engine verified locally**: Godot `4.7.1.stable.official.a13da4feb`, headless import and both preview scenes run clean.
- **Assets** under `assets/kaykit/`: two KayKit Adventurers characters (`Knight.glb`, `Mage.glb`) that share one rig and already carry `Idle`, `Walking_A`, `Interact` clips, five Furniture Bits props and five Restaurant Bits objects. `docs/assets_provenance.md` records source commit, size and SHA-256 for every file.
- **Dialogue plugin**: Dialogue Manager `v4.2.0` (MIT) in `addons/dialogue_manager/`. LEX-01 uses two of its node types as widgets - `DialogueLabel` for the spoken sentence and `DialogueResponsesMenu` for the two answer sentences - so an answer set comes straight from the scenario JSON and no `.dialogue` graph is needed for gameplay. `content/dialogue/prep_smoke.dialogue` remains the plugin smoke file.
- **Content**: `data/vocabulary/de_a1_starter.json` (47 Goethe-A1-verified lemmas: 23 nouns, 12 verbs, 7 adjectives, 2 prepositions, 1 adverb, 2 everyday expressions), `data/scenarios/lex01_starter.json` (15 scenarios), `data/scenarios/lex01_extension.json` (2 more scenarios, which is the data-only proof for Issue #2) and `data/scenarios/tav01_sample_shift.json` (10 sample tavern-shift scenarios), plus `data/room/lex01_room.json` for where things stand. `docs/tav01_learning_plan.md` plans the rest of the shift on that data.

Preview and regression scenes, all safe to run:

- `scenes/main.tscn` - the playable LEX-01 room.
- `scenes/prep_preview.tscn` - the two characters and the ten props; a short probe plays idle/walk/interact and exits.
- `scenes/prep_dialogue_smoke.tscn` - prints one German line, its two options and both branch outcomes.

## Playing LEX-01

Run `scenes/main.tscn` in Godot. Mouse only:

| Situation | What you do |
| --- | --- |
| `find_select` | Click the object the sentence asks for. |
| `bring_deliver` | Click an object to pick it up (the HUD names what you hold), then click the target. Click another object to swap what you hold. Only the delivery counts as an answer. |
| `respond` | Click one of the two answer sentences. The objects those sentences name are in the room, and the one in focus is highlighted. |

- A wrong answer costs an attempt, never the run: the objects move and the answer order changes, so guessing by position cannot work.
- **Weiter ohne Antwort** ends a situation without an answer; it is recorded as skipped, never as correct.
- **Tag beenden** shows the end-of-day summary and **Neuer Tag** starts the next day found in the data. **Neuer Durchgang** clears the saved run.
- `Esc` quits.

Progress is saved in `user://lex01_progress.json` (Godot's per-user data folder). Per lemma the game records *encountered, correct, incorrect, revisited, skipped* and *seen as an answer alternative*. There is deliberately **no mastery score and no spaced repetition**: nothing in this slice measures retention, so nothing reports it. English glosses from the vocabulary appear **only** in the end-of-day summary; every text during play is German.

## Adding a learning situation (no code)

`scripts/lex01_content.gd` reads every `*.json` in `data/scenarios/`. To add a situation, add a record to an existing file or add a new file with the same shape:

```json
{
  "schema_version": 1,
  "scenario_count": 1,
  "presentation_note": "...",
  "distractor_note": "...",
  "scenarios": [
    {
      "id": "x03", "day": 2, "action_type": "find_select",
      "npc": "mage", "context": "kitchen",
      "verb_lemma_id": "suchen", "target_lemma_ids": ["tomate"],
      "distractor_lemma_ids": ["kartoffel", "broetchen"],
      "utterance_de": "Such die Tomate!",
      "options": [
        { "id": "a", "label_de": "die Kartoffel", "scene_object": "res://assets/kaykit/items/food_ingredient_potato.gltf", "lemma_ids": ["kartoffel"] }
      ],
      "correct_option_id": "b",
      "feedback_correct_de": "...", "feedback_wrong_de": "..."
    }
  ]
}
```

Rules the data has to respect (CI enforces them, and the game prints them as `CONTENT_ERROR` instead of crashing):

- `action_type` is one of `find_select`, `bring_deliver`, `respond`.
- Option ids stay the positional labels `a`, `b`, `c` of the authored order. Correctness is resolved by `correct_option_id`, never by position, and the visible order is re-shuffled on every presentation and every retry.
- `distractor_lemma_ids` = lemmas of the incorrect options minus the lemmas of the correct option.
- `scene_object` paths must exist; `day` decides which day a scenario appears in; `revisit_of` marks a delayed revisit of another scenario id.
- `scene_state` may state where something is: `"broetchen": "on_table"`, `"kartoffel": "in_fridge"`, or `focus_object` / `compared_object` for highlighting. A placement name must be declared in `data/room/lex01_room.json`.

`data/room/lex01_room.json` is the only file that knows positions: `npcs`, `cameras` per `context`, `candidate_slots` per `context` (the kitchen layout is deliberately different from the room layout, so a day-2 revisit is a changed situation), `anchors` for surfaces, `placement_slots` (`on_table`, `in_fridge`), the hold tray and the delivery offset. Nothing in the gameplay scripts contains a German word, a prop path or a coordinate.

- [BOOT-01: bootstrap](https://github.com/ExecBit/language-life-sim/issues/1)
- [PREP-01: asset, dialogue and content preparation](https://github.com/ExecBit/language-life-sim/issues/4)
- [LEX-01: learning vertical slice](https://github.com/ExecBit/language-life-sim/issues/2)

## Open the Godot project

Use Godot **4.7.1** (the version this work was verified with). Open the **repository root** where `project.godot` is located and run `scenes/main.tscn`, or one of the preview scenes above. Godot execution is not validated by GitHub CI; CI checks the repository structure and validates every scenario file and the room layout. Two focused probes exist for local verification:

```powershell
$godot = "C:/Users/agdei/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.1-stable_win64_console.exe"

# whole learning loop over both days, headless, on the real scene
& $godot --headless --path . --quit-after 20000 res://scenes/main.tscn -- --probe --seed 1234
# a real mouse click on a prop, on a delivery target and on an answer button, windowed
& $godot --path . --quit-after 20000 res://scenes/main.tscn -- --probe-input --seed 7
```

Both print `LEX01 PROBE OK` / `LEX01 INPUT PROBE OK` or `... FAIL` with reasons and a non-zero exit code.

## Not verified yet

- **Export and a launched build**: no export templates are installed and there is no `export_presets.cfg`, so an exported build - and whether runtime `load()` of the `.gltf` props works there - is untested. Packaging is a separate task.
- **How the room and HUD look and read**: the probes check behaviour, not visual quality or readability. That is a human judgement.
- **German naturalness of the sentences**, including the two in `lex01_extension.json` and the ten in `tav01_sample_shift.json`, is not verified by any automated check, and neither is the Russian and English wording of the 32 lemmas TAV-01 added (see `docs/assets_provenance.md`).
- **Mouse picking under an arbitrary camera angle**: the input probe clicks projected object centres in the shipped camera framings; it does not sweep every angle.
- `in_fridge` places an item in front of the fridge and highlights it. The committed fridge prop has no door, so "in dem Kühlschrank" is shown rather than opened.

## Development principles

1. **Vocabulary first**: each situation names target lemmas, action, expected outcome and feedback.
2. **Reuse gameplay verbs**: find/select, bring/deliver, respond. Prefer data over a new code path for each item.
3. **Small vertical slice**: one room, two NPCs, 10–15 lemmas, multiple contexts and a delayed revisit.
4. **Fast feedback**: short focused test and one playable smoke check; no custom IK, physically simulated hand-offs, or per-object GPU evidence.
5. **Issues / Project / PR**: Issue defines task, GitHub Project tracks its status, PR holds change + verification. The user alone merges.

See `AGENTS.md` for local-agent instructions. The prior `tavern-language-mvp` repository is independent: do not copy its process constraints or asset pipeline.
