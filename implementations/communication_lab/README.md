# Communication Lab

Independent F6 sandbox for inspecting the German parser, word catalog and composer, with a small local A0–A1 conversation grammar layered in this variant only. The original parser/catalog/composer were copied from dormitory `game/communication/` at main revision `c2b2b8e` (2026-11-11); new dialogue words and intents live only in `communication_lab/`.

## Run

Open `res://implementations/communication_lab/communication_lab.tscn` in the same Godot project and press **F6**. F5 remains the dormitory. Walk near Astera and press **E** to open the composer in the bottom-left HUD position. Enter any German text; use the lower word field and **Tab** to append catalog suggestions. Close with Esc or the close button. **F2** toggles diagnostics. Context controls set Astera busy, her knowledge of the key, key ownership, and a pending offer or clarification. “Reset context” resets the experiment. Attempts are appended to `user://communication_lab_attempts.jsonl`.

The supported resolver is intentionally bounded. It handles the original lab cases (social replies, key location/identification, safe key transfer, opening the door) plus dialogue about a player name, good/low/tired moods, Astera's tiredness and tidying, the unowned cup, offering/declining help, free/work/learning plans, slow speech and farewell. `dialogue_resolver.gd` reports only these known lexical constructions; arbitrary German remains `UNKNOWN`/`UNSUPPORTED` and has no world effect. Questions such as `Warum?` and `Und du?` use the last topic or ask for clarification. The attempt journal stores context before/after, parse result, reply, topic, reaction, emotion and animation ID. Conversation memory is limited to the active lab session.

The lab uses the locally available private Astera VRM when present and falls back to the redistributable Anna VRM on clean checkouts. The closed Astera model is intentionally not included in this PR. A local adapter retargets the Motifect `idle_neutral` clip and the new, lab-owned generated conversation motions to the avatar; generated asset provenance/license and IDs are recorded in [the motion manifest](animations/generated/manifest.json). Anna's redistribution permissions are recorded in [assets/characters/ANNA_LICENSE.md](../../assets/characters/ANNA_LICENSE.md); Motifect attribution/license is in `assets/animations/motifect/README.txt`.

The VRM0 metadata of both available avatar files maps the expression presets to morph indices: `neutral=0`, `angry=1`, `fun=2`, `joy=3`, `sorrow=4`, `surprised=5`, vowels `A–O=39–43`, and blink variants `13–15`. Godot imports these as `morph_N`; the adapter maps the five emotional channels by index and blends them independently from the skeleton motions. The lab uses `fun`, `joy`, `sorrow`, and `surprised` combinations for its named reactions. Eye blink and vowel/mouth movement are available but are not currently driven. `tests/test_lab.gd` checks that a happy state writes the `joy` morph on the loaded avatar.

## Targeted verification

Run the parser/resolver tests with:

```powershell
godot --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd
```

Run an import pass with:

```powershell
godot --headless --path . --editor --quit
```

The test covers the copied parser regression matrix, context-dependent legacy replies, `Ja/Nein` with and without pending offers, `Schlüssel?` clarification followed by a location question, negation without an effect, free text with a missing catalog word, idempotent transfer and reset. It also checks name memory, out-of-order activity/mood questions, contextual `Warum?`/`Und du?`, distinct player moods/plans, help acceptance/refusal, slow-speech context, farewell, unknown phrases without effects, avatar expressions, player interaction range, generated greeting/point motions and return to idle.

## Manual check and limitations

- [ ] F6 launches the one-room scene and Astera is visible (Anna fallback if the private local model is absent).
- [ ] E opens/closes the dialog; input blocks movement while open and movement resumes after closing.
- [ ] Compose, edit and send both catalog text and a word absent from the catalog.
- [ ] Inspect raw input, tokens, parser status/intent/frame, ambiguity, unsupported features, diagnostics, NPC answer and actual effects.
- [ ] Change context, retry a phrase, reset, and confirm play can continue.
- [ ] Standard Cogito HUD is hidden and the Communication panel appears in its bottom-left position when talking.
- [ ] F5 still launches the dormitory.

This lab does not imply understanding of unrestricted German. `Ja/Nein` use only explicit pending context, and item/door effects are a two-object demonstrator, not a quest. Parser gaps are recorded by the regression case and should be fixed separately. Exported candidate launch and in-editor F6/F5 manual checks are reported in the PR according to what was actually run.

## Conversation and laboratory UI

Conversation starts with E near Astera; Esc closes it and restores movement. F2 opens the laboratory from anywhere and pauses movement while editing. The player panel contains the NPC response, editable phrase, catalog search, suggestions, Send, Clear and an F1 word memo grouped by part of speech. H remains available for normal text entry. Enter sends the complete phrase including an unconfirmed search token; Tab appends a selected catalog word. Arrow keys navigate suggestions only while catalog search/list has focus.

The separate laboratory panel is hidden by default. Context controls apply to the next attempt. Four inspector tabs separate parsing (raw input, tokens, full frame, ambiguity, unsupported features and diagnostics), NPC response/effects, live and recorded before/after state, and session history. Select a historical attempt to inspect it without restoring the world. Recall loads its text for editing and an explicit resubmission under the current context. Reset restores context while retaining history for comparison. Inspector text can be selected and copied.

Automated visual/workflow verification: run `Godot_v4.7.1-stable_win64_console.exe --path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/capture_ui.gd`. Captures go to ignored `.local/commlab-*.png`; assertions cover composer submission, history recall, reset and movement restoration. See the verification report for observed shared-addon warnings.

## Conversation examples and boundaries

- `E` opens with Astera's greeting. `Ich heiße Alex`, `Alex`, or `Ich bin Alex` records the player's name.
- Ask `Was machst du?` at any point; `Wie geht's dir?` can be asked before or after it. `Warum?` receives an explanation only after Astera has mentioned tiredness/work; otherwise she asks what the player means.
- `Sehr gut!` / `Gut, danke.` and `Nicht so gut.` / `Ich bin müde.` have different reactions. `Ich habe frei.`, `Ich arbeite.`, and `Ich lerne Deutsch.` also lead to different replies.
- `Kann ich helfen?` followed by `Ja, bitte!` or `Nein, danke.` distinguishes acceptance from refusal. The offer does not move the cup or invent a physical handover. Learning German sets a temporary slow-speech preference only after an explicit yes.
- `Und du?` returns Astera's mood when that is the active topic; elsewhere it asks for clarification. `Tschüss` / `Bis später!` plays the farewell gesture.
- Unknown constructions stay typeable and are reported honestly. This grammar is a deliberate phrase/intent subset, not unrestricted German comprehension; no LLM or hidden effect is used.

Latest targeted verification: `tests/test_lab.gd` prints `COMMUNICATION_LAB_TESTS: 0 failure(s)`. `tests/capture_ui.gd` prints `UI_WORKFLOW: PASS` and writes opening, conversation, memo, parse and response/effect captures to `.local/`. The Cogito startup emits missing prologue InputMap names and null shared audio/slide-audio errors in headless/CLI runs; these pre-existing shared-addon issues are outside this variant and remain visible in the log.
