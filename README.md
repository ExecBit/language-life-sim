# Language Life Sim

A small Godot 4 learning-game prototype. The goal is to test whether **10–15 everyday German lemmas** can be learned and revisited through different playable situations, before expanding toward a 4,000-word curriculum. The current starter list is Goethe-A1-derived, not frequency-ranked.

## Current status

PREP-01 prepared the prerequisites for the learning slice. The main scene is still the geometric placeholder from BOOT-01, and **no LEX-01 gameplay exists yet**: no find/bring/respond handling, no progress tracking, no day cycle.

What is in place now:

- **Engine verified locally**: Godot `4.7.1.stable.official.a13da4feb`, headless import and both preview scenes run clean.
- **Assets** under `assets/kaykit/`: two KayKit Adventurers characters (`Knight.glb`, `Mage.glb`) that share one rig and already carry `Idle`, `Walking_A`, `Interact` clips, five Furniture Bits props and five Restaurant Bits objects. `docs/assets_provenance.md` records source commit, size and SHA-256 for every file.
- **Dialogue plugin**: Dialogue Manager `v4.2.0` (MIT) in `addons/dialogue_manager/`, with `content/dialogue/prep_smoke.dialogue` as a one-line, two-option German smoke file.
- **Content handoff**: `data/vocabulary/de_a1_starter.json` (15 Goethe-A1-verified lemmas) and `data/scenarios/lex01_starter.json` (15 authored scenarios across `find_select`, `bring_deliver`, `respond`). Data only - nothing reads it yet.

Preview scenes, both safe to run:

- `scenes/prep_preview.tscn` - the two characters and the ten props; a short probe plays idle/walk/interact and exits.
- `scenes/prep_dialogue_smoke.tscn` - prints one German line, its two options and both branch outcomes.

- [BOOT-01: bootstrap](https://github.com/ExecBit/language-life-sim/issues/1)
- [PREP-01: asset, dialogue and content preparation](https://github.com/ExecBit/language-life-sim/issues/4)
- [LEX-01: learning vertical slice](https://github.com/ExecBit/language-life-sim/issues/2)

## Open the Godot project

Use Godot **4.7.1** (the version this preparation was verified with). Open the **repository root** where `project.godot` is located, then run `scenes/main.tscn` for the placeholder room, or one of the two preview scenes above. Godot execution is not validated by GitHub CI; CI only checks the repository structure and the two starter content files.

## Development principles

1. **Vocabulary first**: each situation names target lemmas, action, expected outcome and feedback.
2. **Reuse gameplay verbs**: find/select, bring/deliver, respond. Prefer data over a new code path for each item.
3. **Small vertical slice**: one room, two NPCs, 10–15 lemmas, multiple contexts and a delayed revisit.
4. **Fast feedback**: short focused test and one playable smoke check; no custom IK, physically simulated hand-offs, or per-object GPU evidence.
5. **Issues / Project / PR**: Issue defines task, GitHub Project tracks its status, PR holds change + verification. The user alone merges.

See `AGENTS.md` for local-agent instructions. The prior `tavern-language-mvp` repository is independent: do not copy its process constraints or asset pipeline.
