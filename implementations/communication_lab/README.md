# Communication Lab

An independent A0–A1 German language experiment in `implementations/communication_lab/`. Issue #68 replaces the earlier social exchange with Astera's single-room **No Pass** RPG conversation. There is no real door, prop, second character or pass item.

## Play

Open `res://implementations/communication_lab/communication_lab.tscn` in Godot and press **F6**. Walk up to Astera and press **E**. Choose a Russian action as a communication goal, then write a free German sentence. The menu selection alone never performs an action; the sentence must match the current proposition, speaker, role and polarity. Unknown, compound or unsupported input stays on the current node and applies no story effects. Grammar errors can be corrected without penalty.

**F1** opens the searchable A0–A1 German–Russian word memo. **F2** opens the laboratory directly on **Граф диалога**. The native `GraphEdit` is built from the same `first_talk.json` graph used by `DialogueGraph` and `LabSession`; it shows all authored transitions and endings. Current and visited nodes have distinct card styles, the last real transition is gold, and clicking a card shows its outgoing conditions and actions. Use the graph controls to pan or zoom, **К текущему** to center the active node, and **Текущее состояние** to leave a read-only historical attempt. The route history is displayed beneath the graph. Reset clears the live conversation; reopening a completed ending follows a return edge and does not grant the outcome again.

Astera starts with roster membership but no pass, technician status, or stored name; access is `none`, trust is `neutral`, and the message promise is false. The authored graph has 18 stable nodes: `G00_GATE`, `G10_NO_CARD`, `G20_RULES`, `G30_NAME`, `G40_REGISTERED`, `G50_CONFIRM`, `G60_TECHNICIAN`, `G70_EXPOSED`, `G80_WARNING`, `G90_DEAL`, `G100_INSTRUCTION`, `G110_REPEAT`, `G120_REFUSED_DEAL`, `E_OFFICIAL`, `E_FAVOR`, `E_LEAVE`, `E_CAUGHT`, and `G130_RETURN`. The four endings are distinct: official access, conditional favor, unpunished departure, and caught deception.

## Acceptance routes

`tests/test_issue68.gd` exercises all eight required routes:

1. `G00_GATE → G10_NO_CARD → G30_NAME → G40_REGISTERED → G50_CONFIRM → E_OFFICIAL`
2. `G00_GATE → G20_RULES → G40_REGISTERED → G50_CONFIRM → E_OFFICIAL`
3. `G00_GATE → G10_NO_CARD → G90_DEAL → G100_INSTRUCTION → E_FAVOR`
4. As route 3, with `G110_REPEAT` before `E_FAVOR`
5. `G00_GATE → G60_TECHNICIAN → G70_EXPOSED → G20_RULES → G40_REGISTERED → G50_CONFIRM → E_OFFICIAL`
6. `G00_GATE → G60_TECHNICIAN → G70_EXPOSED → G80_WARNING → E_CAUGHT`
7. `G00_GATE → G10_NO_CARD → G90_DEAL → G120_REFUSED_DEAL → E_LEAVE`
8. Reopen after `E_OFFICIAL` or `E_FAVOR` to reach `G130_RETURN` without repeating an effect.

The same suite checks productive German intent families, positive/negative possession, first/second-person help roles, false technician claims, short answers bound to an open proposition, menu/intent mismatches, and no-effects behavior for unknown or compound sentences. Graph validation checks reachability, stable edge IDs, guards, effects, terminal nodes and all 61 transitions. The existing Issue #65 parser regression remains in `tests/test_issue65.gd`.

## Targeted verification

`tests/test_vocabulary_sync.gd` checks that the actual Composer and F1 use the same scenario words and translations, including `Techniker`, and that all authored dialogue/confirmation/fallback words are covered. Full constructions appear in F1; individual words appear in both interfaces.

F1 and completion prioritize frequent words in this scenario, counted across authored dialogue, confirmations, constructions and each player's action vocabulary. Full constructions are always below individual words. F1 also searches Russian action labels: for example, `времен` finds words for requesting a temporary pass, including `Pass` and `vorläufigen`. Each non-system action declares its required `vocabulary` and relevant `search_words` in the scenario data; the coverage test checks all 19 actions.

Run the source-project suites with the installed Godot console executable (do not export this lab):

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://implementations/communication_lab/tests/test_issue68.gd --quit-after 120
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://implementations/communication_lab/tests/test_productive_intents.gd --quit-after 120
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd --quit-after 120
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://implementations/communication_lab/tests/test_issue65.gd --quit-after 120
Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --quit
```

For a rendered capture, run `Godot_v4.7.1-stable_win64.exe --path . --script res://implementations/communication_lab/tests/capture_issue68_graph.gd --quit-after 600`; it saves the source viewport image to ignored `.local/issue68-f2-graph.png`. For a manual check, open the source scene with **F6**, press **E** near Astera, then **F2**. The first view should show the live graph rather than a separate diagram; send a supported line to highlight a route, click nodes for diagnostics, and inspect a prior attempt in **История**. No EXE, PCK or export-template build is part of this task.

The resolver is a bounded, explainable German subset and does not claim unrestricted comprehension. The graph JSON is the single scenario source; local gameplay code validates a sentence, chooses one guarded authored edge and applies only that edge's declared effects.

The lab uses the licensed AvatarSample_B model; see [its attribution and conditions](assets/characters/AVATAR_SAMPLE_B_LICENSE.md). Generated animation provenance remains in [the motion manifest](animations/generated/manifest.json). Shared addons and other implementations are not part of this variant.

F2 presents a compact left-to-right story diagram. Primary story arrows are prominent; repeat/return edges are faint and become prominent when their source is selected. All 61 transitions remain native GraphEdit connections. The side inspector contains full NPC lines, actions, guards and consequences; **Весь сюжет** fits all 18 nodes, and **К текущему** selects and centers the live node. Display-only `debug_position`/`overview` annotations live beside the runtime graph data.
