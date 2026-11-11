# Communication Lab

Independent F6 sandbox for inspecting the German parser, word catalog and composer, with a small local A0–A1 conversation grammar layered in this variant only. The original parser/catalog/composer were copied from dormitory `game/communication/` at main revision `c2b2b8e` (2026-11-11); new dialogue words and intents live only in `communication_lab/`.

## Run

Greeting prefixes can accompany an introduction or simple mood reply: `Hallo ich bin Alex`, `Hallo! Ich heiße Alex.`, `Hi, ich bin Alex`, or `Hallo, ich bin müde`. The main intent produces one NPC reply; F2 preserves the complete token sequence and shows the greeting prefix. Unsupported continuations and negated introductions do not save a name or complete a goal.

Open `res://implementations/communication_lab/communication_lab.tscn` in the same Godot project and press **F6**. F5 remains the dormitory. Walk near Astera and press **E** to start a smooth waist-up camera close-up and open the full-width dialogue panel at the bottom. Enter any German text; **Ctrl+Tab** switches between the main phrase and word search, **Down/Up** moves between those rows, **Tab** cycles suggestions and **Space** inserts the selected word. Both drafts stay intact while switching. Close with Esc or the close button. **F1** opens a searchable German–Russian vocabulary memo with whole-phrase translations; **F2** opens diagnostics. Six Russian conversation goals are independent navigation cues, based on handled dialogue intents and evidence rather than language mastery. F2 controls Astera busy state, NPC/player mood, name knowledge, topic, pending question and offered help. Reset clears dialogue and goal progress. Attempts are appended to `user://communication_lab_attempts.jsonl`.

The supported resolver is intentionally bounded. It handles the player name, good/low/tired moods, Astera's mood/activity, offering/declining help, free/work/learning plans, slow speech and farewell. NPC replies use simple A0 language with recurring words; F1 translates exact forms and whole expressions such as `Wie geht's dir?`, `Ich arbeite heute viel.`, and `Bis später!`. After a long pause, Astera can gently tease `Du bist sehr still!`; an active conversation does not force a reply. Help responses acknowledge the offer without inventing a physical task. Arbitrary German remains `UNKNOWN`/`UNSUPPORTED` and has no world effect. Questions such as `Warum?` and `Und du?` use context or ask for clarification. The attempt journal stores context before/after, parse result, reply, topic, reaction, emotion, animation ID and objective evidence.

The lab currently uses **AvatarSample_B**, the standard VRoid sample copied without modification into this variant. See [its attribution and conditions](assets/characters/AVATAR_SAMPLE_B_LICENSE.md). The character name/dialogue remains Astera. The scene root's **NPC Avatar Path** selects the appearance; the previous private Astera path can be selected locally (`res://assets/characters/private/astera.vrm`), and an unavailable selection falls back to the licensed Anna model. The private Astera binary remains uncommitted. A local adapter retargets the existing Motifect idle and lab-generated conversation motions; [the motion manifest](animations/generated/manifest.json) retains their provenance. Shared addons/assets are untouched.

The VRM0 metadata of AvatarSample_B, local Astera and Anna maps the expression presets to morph indices: `neutral=0`, `angry=1`, `fun=2`, `joy=3`, `sorrow=4`, `surprised=5`, vowels `A–O=39–43`, and blink variants `13–15`. Godot imports these as `morph_N`; the adapter maps the five emotional channels by index and blends them independently from the skeleton motions. The lab uses `fun`, `joy`, `sorrow`, and `surprised` combinations for its named reactions. Eye blink and vowel/mouth movement are available but are not currently driven. `tests/test_lab.gd` checks that a happy state writes the `joy` morph on the loaded avatar.

## Targeted verification

Run the parser/resolver tests with:

```powershell
godot --headless --path . --script res://implementations/communication_lab/tests/test_lab.gd
```

Run an import pass with:

```powershell
godot --headless --path . --editor --quit
```

The test covers the copied parser matrix, context-dependent greetings, `Ja/Nein` with and without pending offers, legacy object frames without world effects, negation, free text with a missing catalog word and reset. It also checks name memory, independent objective progress/evidence, contextual `Warum?`/`Und du?`, distinct player moods/plans, silence teasing, help acceptance/refusal, slow-speech context, A0 form coverage/phrase translation, avatar expressions, player interaction range and generated greeting/player-directed gesture with return to idle.

## Manual check and limitations

- [ ] F6 launches the one-room scene and the NPC using AvatarSample_B is visible.
- [ ] E opens/closes the dialog; input blocks movement while open and movement resumes after closing.
- [ ] Compose, edit and send both catalog text and a word absent from the catalog.
- [ ] Inspect raw input, tokens, parser status/intent/frame, ambiguity, unsupported features, diagnostics, NPC answer and actual effects.
- [ ] Change context, retry a phrase, reset, and confirm play can continue.
- [ ] Standard Cogito HUD is hidden and the Communication panel spans the bottom screen width while a close-up camera frames Astera above the waist.
- [ ] F5 still launches the dormitory.

This lab does not imply understanding of unrestricted German. `Ja/Nein` use only explicit pending context. Key/door cases remain isolated parser regressions; the room has no props or object effects. Parser gaps are recorded by regression cases and should be fixed separately. Exported candidate launch and in-editor F6/F5 manual checks are reported in the PR according to what was actually run.

## Conversation and laboratory UI

Conversation starts with E near Astera; Esc closes it and restores movement. F2 opens the laboratory from anywhere and pauses movement while editing. The player panel contains a scrollable, speaker-labelled transcript of player and NPC messages, an editable phrase, catalog search, suggestions, Send, Clear and an F1 memo with its own search field, whole-phrase translations and words grouped by part of speech. H remains available for normal text entry. Enter sends the complete phrase including an unconfirmed search token; Tab cycles catalog suggestions (Shift+Tab cycles backwards); Space inserts the selected word from the search field/list. In the main phrase field, Space stays ordinary text input. Arrow keys navigate suggestions only while catalog search/list has focus.

The separate laboratory panel is hidden by default. Context controls apply to the next attempt. Four inspector tabs separate parsing (raw input, tokens, full frame, ambiguity, unsupported features and diagnostics), NPC response/effects, live and recorded before/after state, and session history. Select a historical attempt to inspect it without restoring the world. Recall loads its text for editing and an explicit resubmission under the current context. Reset restores context while retaining history for comparison. Inspector text can be selected and copied.

Automated visual/workflow verification: run `Godot_v4.7.1-stable_win64_console.exe --path . --rendering-method gl_compatibility --script res://implementations/communication_lab/tests/capture_ui.gd`. Captures go to ignored `.local/commlab-*.png`; assertions cover composer submission, history recall, reset and movement restoration. See the verification report for observed shared-addon warnings.

## Conversation examples and boundaries

- `E` opens with Astera's greeting. `Ich heiße Alex`, `Alex`, or `Ich bin Alex` records the player's name.
- Ask `Was machst du?` at any point; `Wie geht's dir?` can be asked before or after it. `Warum?` receives an explanation only after Astera has mentioned tiredness/work; otherwise she asks what the player means.
- `Sehr gut!` / `Gut, danke.` and `Nicht so gut.` / `Ich bin müde.` have different reactions. `Ich habe frei.`, `Ich arbeite.`, and `Ich lerne Deutsch.` also lead to different replies.
- `Kann ich helfen?` or `Hilfe?` opens the help exchange; `Ja, bitte!` and `Nein, danke.` remain distinct responses. The social reply does not imply an unimplemented physical action. Learning German sets a temporary slow-speech preference only after an explicit yes.
- `Und du?` returns Astera's mood when that is the active topic; elsewhere it asks for clarification. `Tschüss` / `Bis später!` plays the farewell gesture.
- Unknown constructions stay typeable and are reported honestly. This grammar is a deliberate phrase/intent subset, not unrestricted German comprehension; no LLM or hidden effect is used.

Latest targeted verification: `tests/test_lab.gd` prints `COMMUNICATION_LAB_TESTS: 0 failure(s)`. `tests/capture_ui.gd` prints `UI_WORKFLOW: PASS` and writes opening, conversation, memo, parse and response/effect captures to `.local/`. The Cogito startup emits missing prologue InputMap names and null shared audio/slide-audio errors in headless/CLI runs; these pre-existing shared-addon issues are outside this variant and remain visible in the log.

The conversation camera moves to its close-up over 0.6 seconds; closing restores the original player camera and movement. The room contains no object props; Astera's compatible pointing gesture now directs attention toward the player.

Sent messages clear the draft and remain in the conversation transcript. New NPC replies reveal progressively; click the transcript to show the full reply immediately. Closing/reopening keeps the conversation; reset clears it while retaining the separate diagnostic attempt history. Legacy replies now select conversation gestures instead of idle, and repeating a gesture restarts its timeline.
