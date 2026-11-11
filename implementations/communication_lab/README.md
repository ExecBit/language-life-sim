# Communication Lab

Independent F6 sandbox for inspecting the existing German parser, word catalog and composer. The implementation is copied from dormitory `game/communication/parser.gd`, `word_catalog.gd` and `word_composer.gd` at main revision `c2b2b8e` (2026-11-11); only its internal script paths point to this variant. Grammar changes belong in a separate issue.

## Run

Open `res://implementations/communication_lab/communication_lab.tscn` in the same Godot project and press **F6**. F5 remains the dormitory. Walk near Anna and press **E** to open the composer. Enter any German text; use the lower word field and **Tab** to append catalog suggestions. Close with Esc or the close button. **F2** toggles diagnostics. Context controls set Anna busy, her knowledge of the key, key ownership, and a pending offer or clarification. “Reset context” resets the experiment. Attempts are appended to `user://communication_lab_attempts.jsonl`.

The supported resolver is intentionally small: greetings/social replies, repeat request, key location/identification, handing over a key held by Anna, opening the door, and a few safe acknowledgements. Parser recognition is not world execution: only explicit resolver cases have effects. Unknown, unsupported and clarification results never modify the world. The same request can produce a different answer as context changes.

Anna's shared VRM asset is used in place, without copying the asset. A small local adapter retargets the existing Motifect `idle_neutral` clip to the character skeleton so she stands calmly instead of remaining in the imported rest pose. The raw animation remains in the shared asset directory because its license disallows redistributing the raw file as a standalone product. Anna's redistribution permissions are recorded in [assets/characters/ANNA_LICENSE.md](../../assets/characters/ANNA_LICENSE.md); the Motifect animation pack attribution/license is in `assets/animations/motifect/README.txt`. The player and Cogito addons are shared project dependencies.

## Targeted verification

Run the parser/resolver tests with:

```powershell
godot --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd
```

Run an import pass with:

```powershell
godot --headless --path . --editor --quit
```

The test covers R01–R15 and W01–W07 parser/context cases from the existing specification, context-dependent replies, `Ja/Nein` with and without pending offers, `Schlüssel?` clarification followed by a location question, negation without an effect, free text with a missing catalog word, idempotent transfer and reset.

## Manual check and limitations

- [ ] F6 launches the one-room scene and Anna is visible.
- [ ] E opens/closes the dialog; input blocks movement while open and movement resumes after closing.
- [ ] Compose, edit and send both catalog text and a word absent from the catalog.
- [ ] Inspect raw input, tokens, parser status/intent/frame, ambiguity, unsupported features, diagnostics, NPC answer and actual effects.
- [ ] Change context, retry a phrase, reset, and confirm play can continue.
- [ ] F5 still launches the dormitory.

This lab does not imply understanding of unrestricted German. `Ja/Nein` use only explicit pending context, and item/door effects are a two-object demonstrator, not a quest. Parser gaps are recorded by the regression case and should be fixed separately. Exported candidate launch and in-editor F6/F5 manual checks are reported in the PR according to what was actually run.
