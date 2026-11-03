# Language Life Sim

A small Godot 4 learning-game prototype. The goal is to test whether **10–15 high-frequency German words** can be learned and revisited through different playable situations, before expanding toward a 4,000-word curriculum.

## Current status

This repository is a **clean bootstrap only**. The initial scene is a geometric placeholder, not the playable learning vertical slice. No NPCs, content packs, dialogue plugin, audio, mastery model, or validated word list are installed yet.

- [BOOT-01: bootstrap](https://github.com/ExecBit/language-life-sim/issues/1)
- [LEX-01: learning vertical slice](https://github.com/ExecBit/language-life-sim/issues/2)

## Open the Godot project

Use a locally installed Godot 4.x editor (target: 4.7.1). Open the **repository root** where `project.godot` is located, then run the main scene. The scene is a neutral room/floor/cube placeholder. Godot execution is not validated by GitHub CI.

## Development principles

1. **Vocabulary first**: each situation names target lemmas, action, expected outcome and feedback.
2. **Reuse gameplay verbs**: find/select, bring/deliver, respond. Prefer data over a new code path for each item.
3. **Small vertical slice**: one room, two NPCs, 10–15 lemmas, multiple contexts and a delayed revisit.
4. **Fast feedback**: short focused test and one playable smoke check; no custom IK, physically simulated hand-offs, or per-object GPU evidence.
5. **Issues / Project / PR**: Issue defines task, GitHub Project tracks its status, PR holds change + verification. The user alone merges.

See `AGENTS.md` for local-agent instructions. The prior `tavern-language-mvp` repository is independent: do not copy its process constraints or asset pipeline.
