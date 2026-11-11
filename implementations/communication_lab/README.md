# Communication Lab

Independent F6 sandbox for inspecting the existing German parser, word catalog and composer. The implementation is copied from dormitory `game/communication/parser.gd`, `word_catalog.gd` and `word_composer.gd` at main revision `c2b2b8e` (2026-11-11); parser/catalog semantics are unchanged; the local composer presentation and keyboard routing are adapted to the lab. Grammar changes belong in a separate issue.

## Run

Open `res://implementations/communication_lab/communication_lab.tscn` in the same Godot project and press **F6**. F5 remains the dormitory. Walk near Astera and press **E** to open the composer in the bottom-left HUD position. Enter any German text; use the lower word field and **Tab** to append catalog suggestions. Close with Esc or the close button. **F2** toggles diagnostics. Context controls set Astera busy, her knowledge of the key, key ownership, and a pending offer or clarification. “Reset context” resets the experiment. Attempts are appended to `user://communication_lab_attempts.jsonl`.

The supported resolver is intentionally small: greetings/social replies, repeat request, key location/identification, handing over a key held by Astera, opening the door, and a few safe acknowledgements. Parser recognition is not world execution: only explicit resolver cases have effects. Unknown, unsupported and clarification results never modify the world. The same request can produce a different answer as context changes.

The lab uses the locally available private Astera VRM when present and falls back to the redistributable Anna VRM on clean checkouts. The closed Astera model is intentionally not included in this PR; the fallback keeps F6 runnable without it. A local adapter retargets the existing Motifect `idle_neutral` clip to the character skeleton. The raw animation remains in the shared asset directory because its license disallows redistributing the raw file as a standalone product. Anna's redistribution permissions are recorded in [assets/characters/ANNA_LICENSE.md](../../assets/characters/ANNA_LICENSE.md); the Motifect animation pack attribution/license is in `assets/animations/motifect/README.txt`. The player and Cogito addons are shared project dependencies. The copied parser/catalog still uses its original internal addressee ID and vocabulary.

## Targeted verification

Run the parser/resolver tests with:

```powershell
godot --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd
```

Run an import pass with:

```powershell
godot --headless --path . --editor --quit
```

The test covers R01–R15 and W01–W07 parser/context cases from the existing specification, context-dependent replies, `Ja/Nein` with and without pending offers, `Schlüssel?` clarification followed by a location question, negation without an effect, free text with a missing catalog word, idempotent transfer and reset. It also checks the hidden Cogito HUD, bottom-left Communication panel anchors, selected avatar path and active retargeted idle animation.

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

Conversation starts with E near Astera; Esc closes it and restores movement. F2 opens the laboratory from anywhere and pauses movement while editing. The player panel contains the NPC response, editable phrase, catalog search, suggestions, Send and Clear. Enter sends the complete phrase including an unconfirmed search token; Tab appends a selected catalog word. Arrow keys navigate suggestions only while catalog search/list has focus.

The separate laboratory panel is hidden by default. Context controls apply to the next attempt. Four inspector tabs separate parsing (raw input, tokens, full frame, ambiguity, unsupported features and diagnostics), NPC response/effects, live and recorded before/after state, and session history. Select a historical attempt to inspect it without restoring the world. Recall loads its text for editing and an explicit resubmission under the current context. Reset restores context while retaining history for comparison. Inspector text can be selected and copied.

Automated visual/workflow verification: run `Godot_v4.7.1-stable_win64_console.exe --path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/capture_ui.gd`. Captures go to ignored `.local/commlab-*.png`; assertions cover composer submission, history recall, reset and movement restoration. See the verification report for observed shared-addon warnings.
