# Language Life Sim

A small Godot 4 learning-game prototype. The goal is to test whether **10–15 everyday German lemmas** can be learned and revisited through different playable situations, before expanding toward a 4,000-word curriculum. The current starter list is Goethe-A1-derived, not frequency-ranked.

## Current status

**LEX-01 is playable, from inside a tavern.** `scenes/main.tscn` is the learning room: since TAV-03 (Issue #10) it is a 12 x 12 m tavern with a bar counter, a kitchen corner with a stove and storage crates, three guest tables with chairs, a doorway you start in front of, and three people in it - a Mage at the storage end, a Knight behind the counter and a Gast at a table. They give short German sentences, and the player walks up to them, looks through a crosshair and answers by acting on the object the sentence names, by carrying an object to a target, or by choosing a spoken answer. Progress per lemma is tracked and some situations repeat a lemma one simulated day later in a changed context.

The room itself is data: `data/room/lex01_room.json` names every wall, table, chair, crate and lamp with its model, position and whether the player walks into it, and `scripts/lex01_interior.gd` stands them up. Adding a table to the tavern is one JSON entry, not a code change.

All content lives in JSON. Adding a learning situation means adding or editing a scenario record - no gameplay script, no new asset, no new test file.

What is in place now:

- **Engine verified locally**: Godot `4.7.1.stable.official.a13da4feb`, headless import and both preview scenes run clean.
- **Assets** under `assets/kaykit/`: three KayKit Adventurers characters (`Knight.glb`, `Mage.glb`, `Rogue_Hooded.glb`) that share one rig and already carry `Idle`, `Walking_A`, `Interact` clips, five Furniture Bits props, five Restaurant Bits objects and the 20 room models the tavern is assembled from (walls, doorway, windows, bar counter, wall cabinets, stove, crates, tables, chairs, stools, lamps, rugs, pictures, pot, menu stand). All of them come from the three pinned KayKit commits and the two shared texture atlases already in the repository, so TAV-03 introduced no new licence or texture. `docs/assets_provenance.md` records source commit, size and SHA-256 for every file.
- **Dialogue plugin**: Dialogue Manager `v4.2.0` (MIT) in `addons/dialogue_manager/`. LEX-01 uses two of its node types as widgets - `DialogueLabel` for the spoken sentence and `DialogueResponsesMenu` for the two answer sentences - so an answer set comes straight from the scenario JSON and no `.dialogue` graph is needed for gameplay. `content/dialogue/prep_smoke.dialogue` remains the plugin smoke file.
- **Content**: `data/vocabulary/de_a1_starter.json` (47 Goethe-A1-verified lemmas: 23 nouns, 12 verbs, 7 adjectives, 2 prepositions, 1 adverb, 2 everyday expressions), `data/scenarios/lex01_starter.json` (15 scenarios), `data/scenarios/lex01_extension.json` (2 more scenarios, which is the data-only proof for Issue #2) and `data/scenarios/tav01_sample_shift.json` (10 sample tavern-shift scenarios), plus `data/room/lex01_room.json` for where things stand. `docs/tav01_learning_plan.md` plans the rest of the shift on that data.

Preview and regression scenes, all safe to run:

- `scenes/main.tscn` - the playable LEX-01 tavern.
- `scenes/prep_preview.tscn` - the two characters and the ten props; a short probe plays idle/walk/interact and exits.
- `scenes/prep_dialogue_smoke.tscn` - prints one German line, its two options and both branch outcomes.

## Playing LEX-01

Run `scenes/main.tscn` in Godot (F5). TAV-02 (Issue #9) made the room first-person, so a run starts with a briefing overlay; close it and you are standing just inside the tavern door, looking north down the room to the bar:

| Control | What it does |
| --- | --- |
| `W` `A` `S` `D` | Walk. |
| Mouse | Look around. The mouse is captured while you play, so moving it turns the view instead of a cursor. |
| `E` or left click | Act on whatever the crosshair in the middle of the screen is on. The label under the crosshair names it, and an object too far away says so and costs nothing. |
| `Tab` | Free the cursor so the HUD buttons can be clicked, then capture it again. The briefing, the pause menu, the day summary and the answer menu free it by themselves. |
| `Enter` | **Дальше** after an answer. |
| `H` | Open the Russian translation of the German sentence. |
| `X` | **Пропустить** - end the situation without an answer. |
| `F1` | Open the briefing overlay again during a run. |
| `Esc` | Pause: **Продолжить**, **Новый проход** or **Выйти из игры**. `Esc` no longer quits directly. |

| Situation | What you do |
| --- | --- |
| `find_select` | Walk to the object the sentence asks for, put the crosshair on it, press `E`. |
| `bring_deliver` | `E` on the object to pick it up (the HUD names what you hold), then `E` on the person or place it belongs at. `E` on another object swaps what you hold. Only the delivery counts as an answer. |
| `respond` | Look at the room and pick one of the two answer sentences under the German prompt - click it, or use the arrow keys and `Enter`. The objects those sentences name are in the room, and the one in focus is highlighted. |

The player is a capsule and an eye camera with no body mesh, and carrying is abstract: no hands, no hand physics, no IK, no animation. What stops you is the room shell (floor, four walls, ceiling height) plus four marked pieces of furniture: the two bar-counter sections and the two storage crates. Everything else - tables, chairs, stools, lamps, rugs, wall units, the stove, every prop and every NPC - stays clickable-only, so nothing a task can ask about can block or trap you.

- A wrong answer costs an attempt, never the run: the objects move and the answer order changes, so guessing by position cannot work.
- **Пропустить** (key `X`) ends a situation without an answer; it is recorded as skipped, never as correct.
- **Завершить день** shows the end-of-day summary and **Новый день** starts the next day found in the data. **Новый проход** clears the saved run.
- `Esc` pauses, `Tab` frees the cursor, `F1` reopens the briefing.

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

`data/room/lex01_room.json` is the only file that knows positions: `interior` (the tavern's fixed furniture, since TAV-03), `npcs`, `cameras` per `context` (since TAV-02 this section is read as **where the player is put down** per context - a feet position and an initial facing - and it keeps its name because it is the already-shipped per-context framing contract), `player` for the first-person body and its reach, `candidate_slots` per `context` (the kitchen layout is deliberately different from the room layout, so a day-2 revisit is a changed situation), `anchors` for surfaces, `placement_slots` (`on_table`, `in_fridge`), the hold tray and the delivery offset. Nothing in the gameplay scripts contains a German word, a prop path or a coordinate.

- [BOOT-01: bootstrap](https://github.com/ExecBit/language-life-sim/issues/1)
- [PREP-01: asset, dialogue and content preparation](https://github.com/ExecBit/language-life-sim/issues/4)
- [LEX-01: learning vertical slice](https://github.com/ExecBit/language-life-sim/issues/2)
- [TAV-02: first-person controls in the learning room](https://github.com/ExecBit/language-life-sim/issues/9)
- [TAV-03: compact tavern interior](https://github.com/ExecBit/language-life-sim/issues/10)

## Open the Godot project

Use Godot **4.7.1** (the version this work was verified with). Open the **repository root** where `project.godot` is located and run `scenes/main.tscn`, or one of the preview scenes above. Godot execution is not validated by GitHub CI; CI checks the repository structure and validates every scenario file and the room layout. Two focused probes exist for local verification:

```powershell
$godot = "C:/Users/agdei/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.1-stable_win64_console.exe"

# whole learning loop over both days, headless, on the real scene: also checks the player body,
# the room shell, the reach of the crosshair and where every answer stands relative to the spawn
& $godot --headless --path . --quit-after 20000 res://scenes/main.tscn -- --probe --seed 1234
# a real player walking through the room with a real E key, a real click on the crosshair target,
# a real answer-button click and a real Enter key, walls stopping the walk, windowed
& $godot --path . --quit-after 20000 res://scenes/main.tscn -- --probe-input --seed 7
```

Both print `LEX01 PROBE OK` / `LEX01 INPUT PROBE OK` or `... FAIL` with reasons and a non-zero exit code. `--probe-input` needs a real window: run headless and the HUD's briefing button resolves off-screen, so the probe never gets past the overlay (it stops at `checks=24`). Two of its 102 checks currently fail on `main` for a reason TAV-03 did not introduce and did not fix: an item staged flush against the tall fridge anchor cannot be ray-hit by the eye at 1.6 m, so `E` on it picks nothing (see the input probe's `INPUT_KEY ... aim.kind: ""` on scenario `t01`). The logic probe solves the same records through the real answer path, which is why the failure is invisible there.

## Not verified yet

- **Export and a launched build**: no export templates are installed and there is no `export_presets.cfg`, so an exported build - and whether runtime `load()` of the `.gltf` props works there - is untested. Packaging is a separate task.
- **How the room and HUD look and read**: the probes check behaviour, not visual quality or readability. That is a human judgement.
- **German naturalness of the sentences**, including the two in `lex01_extension.json` and the ten in `tav01_sample_shift.json`, is not verified by any automated check, and neither is the Russian and English wording of the 32 lemmas TAV-01 added (see `docs/assets_provenance.md`).
- **Crosshair aiming at an arbitrary viewing angle**: the input probe aims the eye at the staged objects from the shipped spawn points and walks to them; it does not sweep every angle a player could stand at.
- **Props are clickable, not solid.** They carry collision boxes only so the crosshair can land on them. Since TAV-03 the bar counter and the storage crates are solid furniture and the guest tables, chairs and everything else a scenario can stage are not, so you can still walk through a table - a deliberate trade-off so no task object can ever block or trap the player.
- **How the tavern looks**: the layout, the furniture and the three characters are placed from data and checked for reachability, but whether the room reads as a recognisable tavern is a human judgement the probes cannot make.
- **NPC roles are positional only.** der Ritter stands behind the counter and der Gast at a table, but no scenario record addresses a character as the guest yet, and there is no NPC behaviour: no AI, no navigation, no schedule, no dialogue driven by role.
- `in_fridge` places an item in front of the fridge and highlights it. The committed fridge prop has no door, so "in dem Kühlschrank" is shown rather than opened.

## Development principles

1. **Vocabulary first**: each situation names target lemmas, action, expected outcome and feedback.
2. **Reuse gameplay verbs**: find/select, bring/deliver, respond. Prefer data over a new code path for each item.
3. **Small vertical slice**: one room, two NPCs, 10–15 lemmas, multiple contexts and a delayed revisit.
4. **Fast feedback**: short focused test and one playable smoke check; no custom IK, physically simulated hand-offs, or per-object GPU evidence.
5. **Issues / Project / PR**: Issue defines task, GitHub Project tracks its status, PR holds change + verification. The user alone merges.

See `AGENTS.md` for local-agent instructions. The prior `tavern-language-mvp` repository is independent: do not copy its process constraints or asset pipeline.
