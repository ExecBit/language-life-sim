# Language Life Sim — agent rules

## Priority
Ship the smallest **playable language-learning experiment**. Judge progress by new kinds of meaningful comprehension, not animation fidelity, quantity of generated code, or number of screenshots. Reuse proven tools, assets and Godot built-ins.

## Variant isolation

- Place all variant-owned code, scenes, docs, data, experiments and validation scripts in `implementations/<variant>/`. Do not keep variant-specific documentation or tools at the repository root.
- Do not import any other implementation's files, code, vocabulary or game state. Allowed shared dependencies are `addons/` and the model/animation assets in `assets/`; review any changes to shared dependencies across variants.
- A task for one variant must not modify another variant's implementation. Godot `project.godot` remains the single project-wide technical entry point; it currently starts the dormitory.

## Task entry
- Work **only** on a specific Issue explicitly authorized by the user. Read the full Issue and relevant repository files, then inspect Git status.
- The Issue body is the functional contract. Project Status is the single task-state authority; do not create a local board, status log or handoff document.
- Follow the existing GitHub Project associated with this repository, not the older tavern Project #2. Do not assume the new Project has the same number.
- A small scoped implementation decision can be made independently; ask before changing user-visible goals, scope or acceptance criteria.
- One branch and one PR per authorized task. Link the PR using `Closes #N`. **Never merge or close the Issue for the user.**
- Resume from the Issue/PR, latest branch commits and actual local state. Add an Issue checkpoint comment only if interrupted or truly blocked.

## Scope and implementation
- Treat all legacy tavern files, assets, scene hierarchy, scripts and elaborate verification rules as unrelated.
- Build Godot content from stable, reusable actions and data-driven scenarios. An ordinary vocabulary or scenario addition should not require modifying gameplay scripts.
- Choose ready-made character/prop packs and animation libraries when they reduce friction. Before adoption, confirm license, Godot import and one minimal interaction. Do not make a new toolchain, rigging pipeline, IK, hand physics, procedural town or animation alignment an implicit prerequisite.
- Avoid recreating Godot test frameworks. If an existing test tool fails twice due to the tool itself, stop and simplify the test approach; report any remaining unverified requirement honestly.
- Keep raw temporary logs, screenshots, downloaded assets and test outputs in ignored `.local/`. Commit third-party assets only after checking their redistribution terms and recording attribution where needed.

## Verification proportional to risk
- Documentation/data changes: structural check and simple data/links validation.
- Gameplay change: launch the Godot scene, try the changed action, check important state and basic regression.
- Before requesting merge of a **playable** slice, perform one export and launch of the candidate if the Issue requires it.
- Run small, targeted checks first. Never claim a build, visual result or test PASS without having run it.
- Report concise PASS / FAIL / NOT_TESTED, exact reproduction steps, limitations, and the visible player-facing result in the PR.

## Done
Push the branch, create/update PR, move Project Status to Review **if Project access is available**, and stop. If Project access is unavailable, report it rather than inventing status updates. Only the user can accept and merge.
