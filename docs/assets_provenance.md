# Asset and source provenance (PREP-01)

Every third-party file this repository commits for Issue #4 is listed here with the exact upstream
commit it came from, its byte size and its SHA-256 as measured on the working tree. Re-check with:

```powershell
Get-ChildItem -Recurse -File assets/kaykit | Get-FileHash -Algorithm SHA256
```

(`Get-FileHash` has no `-Recurse` parameter; the file list has to be piped into it.) The command lists
45 files: the 27 third-party files in the tables below, the 2 textures Godot extracted from the
character GLBs (listed under the character table), and the 16 `*.import` sidecars Godot wrote during
import. Only the 27 downloaded files have hash rows here.

## Engine

- Godot `4.7.1.stable.official.a13da4feb` (installed locally through the WinGet package `GodotEngine.GodotEngine`).
- Used for: headless import, `scenes/prep_preview.tscn`, `scenes/prep_dialogue_smoke.tscn`.
- Official release page: https://godotengine.org/download/archive/4.7.1-stable/
- `project.godot` now also carries settings Godot wrote itself during import: `config/features` updated to `4.7`, and `animation/compatibility/default_parent_skeleton_in_mesh_instance_3d=true`, which the KayKit character import relies on.

## Dialogue plugin

- Dialogue Manager `v4.2.0` (release title "for Godot 4.7"), commit `bbf9d2a5f6a9eaa276310eea8b1379a936239d2e`.
- License: MIT — `addons/dialogue_manager/LICENSE` is kept with the copied source.
- Install method: the GitHub release publishes **no zip asset**, so the official tag archive `v4.2.0.tar.gz` (SHA-256 `a427116bff75029b4e3ee4d88b990f07133f242cc9a5ff4d483b2d17b88b7e55`) was downloaded into ignored `.local/downloads/` and `addons/dialogue_manager/` was copied out of it unchanged: 190 files, 726530 bytes.
- `project.godot` enables the plugin and declares the `DialogueManager` autoload by hand. `plugin.gd` would add that autoload with `add_autoload_singleton` when the editor enables the plugin; the entry is written explicitly so a headless run works without opening the editor.

## KayKit asset packs (CC0)

itch.io is the author's storefront, but its "Download Now" button routes through `/purchase` with "Name your own price" and therefore needs an itch.io account. The same packs are published by the author's own GitHub organisation `KayKit-Game-Assets` (linked from kaylousberg.com, and each repository's homepage points back to its itch.io page), already laid out as Godot `addons/` folders. Files were fetched from those pinned commits through `raw.githubusercontent.com`, and only the files listed below were taken — no archives, no whole packs, no FBX duplicates.

| Pack | itch.io page (reference) | Used source repo | Pinned commit |
| --- | --- | --- | --- |
| KayKit Adventurers 1.0 | https://kaylousberg.itch.io/kaykit-adventurers | `KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0` | `672074b73ba276876a19e8816ecdc5241817ab47` |
| KayKit Furniture Bits 1.0 | https://kaylousberg.itch.io/furniture-bits | `KayKit-Game-Assets/KayKit-Furniture-Bits-1.0` | `96d5930a8dbdb363409bbc2d3341718b00e17c9c` |
| KayKit Restaurant Bits 1.0 | https://kaylousberg.itch.io/restaurant-bits | `KayKit-Game-Assets/KayKit-Restaurant-Bits-1.0` | `153c8a7535b48237854cb54ff6890679f8c574d1` |

Each asset directory carries the pack's own `LICENSE.txt`, copied verbatim from the pinned commit. All three state the pack is CC0 ("No rights reserved. You can use it in commercial and non-commercial projects."), so redistribution of these committed files is allowed. CC0 does not require attribution, but the source is recorded above anyway.

Not used: KayKit Prototype Bits and the Kenney Food Kit (no fallback was needed), and the itch-only "KayKit Character Animations" pack — the character GLBs already ship `Idle`, `Walking_A/B/C`, `Interact` and `PickUp` on the same rig, so no separate animation pack and no retargeting was required.

### Characters — KayKit-Character-Pack-Adventures-1.0

| Committed file | Source path in the repo | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `assets/kaykit/characters/Knight.glb` | `addons/kaykit_character_pack_adventures/Characters/gltf/Knight.glb` | 3659532 | `60428e3abc09ba83e595d256e3af8c5c976b46cdae599f0802fc82b4a3445168` |
| `assets/kaykit/characters/Mage.glb` | `addons/kaykit_character_pack_adventures/Characters/gltf/Mage.glb` | 3589240 | `cf898585da33fab50c724d31605fb931eb2912e6d2280092141e98ca81ad507d` |
| `assets/kaykit/characters/LICENSE.txt` | `LICENSE.txt` | 891 | `ae322141814056dda0deea7540d74c41d87aee1da319977cd1bd84ee5a923629` |

Each character GLB embeds its own texture and 76 animation clips, which is why the files are about 3.6 MB each. Subsetting the clips would need a custom glTF pipeline, which Issue #4 explicitly rules out.

Godot's import also extracted the embedded textures into `Knight_knight_texture.png` (14172 bytes) and `Mage_mage_texture.png` (16311 bytes) next to the GLBs. Those two files, and every `*.import` sidecar in this repository, are generated by Godot 4.7.1 from the files above rather than downloaded — they carry no separate licence and are committed because Godot expects import metadata in version control.

### Furniture — KayKit-Furniture-Bits-1.0

| Committed file | Source path in the repo | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `assets/kaykit/furniture/table_medium.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/table_medium.gltf` | 2973 | `fd5e5fe8bbf1d3729b6bd725165d58490e9cbd8dd46ce42314b01f20951a302b` |
| `assets/kaykit/furniture/table_medium.bin` | `addons/kaykit_furniture_bits/Assets/gltf/table_medium.bin` | 9328 | `0e6ba8fd006f673d946979e45487067f4e274be9bbd07816fd371578d2a37518` |
| `assets/kaykit/furniture/cabinet_medium.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/cabinet_medium.gltf` | 3000 | `139419c479c6f8b38ac24e12ce85bf81a199e05067a544db879f7e403446c9dc` |
| `assets/kaykit/furniture/cabinet_medium.bin` | `addons/kaykit_furniture_bits/Assets/gltf/cabinet_medium.bin` | 23304 | `3fc4bff757a36226ecb9504dd6e9d031a5a6c957cb9cc2bb636f12ab49e877e6` |
| `assets/kaykit/furniture/couch.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/couch.gltf` | 3014 | `1a5b74b3a3368870783743c5ce7baa61f45f71131dca66af80b35fd4ac63c222` |
| `assets/kaykit/furniture/couch.bin` | `addons/kaykit_furniture_bits/Assets/gltf/couch.bin` | 21416 | `00f6c9892aa87e2894e049ba47d697307c158c5096eb41bdd44474d5e7ecf5e0` |
| `assets/kaykit/furniture/bed_single_A.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/bed_single_A.gltf` | 3009 | `7b2852bb66bf82cad3e0d03a499b1480879790fa66b645347e3e73761c4fe3f5` |
| `assets/kaykit/furniture/bed_single_A.bin` | `addons/kaykit_furniture_bits/Assets/gltf/bed_single_A.bin` | 22044 | `fc7631db4540d31cbe76dac3c672bc8836ee302796d14bba428bda84b9237f5b` |
| `assets/kaykit/furniture/pictureframe_medium.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/pictureframe_medium.gltf` | 3069 | `768ebf5e81d2d4dfe87276e70b7373ee541592ca409a57067e5e76626a010926` |
| `assets/kaykit/furniture/pictureframe_medium.bin` | `addons/kaykit_furniture_bits/Assets/gltf/pictureframe_medium.bin` | 3176 | `ae120086448ad5f8c8a2e1a360355f9052f4b7848e5b422b00398827b9355e8d` |
| `assets/kaykit/furniture/furniturebits_texture.png` | `addons/kaykit_furniture_bits/Assets/gltf/furniturebits_texture.png` | 15605 | `de62db37a80d1801c3d9eb674890ae04b04469e0c149481a51fa250562c628dc` |
| `assets/kaykit/furniture/LICENSE.txt` | `LICENSE.txt` | 827 | `cd675f2adc31eb5fedaedc1072d8ddc27b917f523682f0561837c03dc56393cb` |

The five props were chosen so each one matches a lemma in `data/vocabulary/de_a1_starter.json`: table_medium = *der Tisch*, cabinet_medium = *der Schrank*, couch = *das Sofa*, bed_single_A = *das Bett*, pictureframe_medium = *das Bild*. `furniturebits_texture.png` is the single shared atlas these `.gltf` files reference.

#### Measured prop sizes behind scenario `s14`

Scenario `s14` asks a comparison between two of these props, so the answer rests on the imported geometry instead of on a size judgement. `tools/prep_probe.gd` merges the world-space AABB of each prop's meshes once per run, prints them and asserts the comparison:

| Prop | Printed size (x, y, z in metres) |
| --- | --- |
| `couch.gltf` (*das Sofa*) | `PROP_SIZE Couch size=(3.000, 1.224, 1.600)` |
| `pictureframe_medium.gltf` (*das Bild*) | `PROP_SIZE PictureframeMedium size=(0.700, 0.900, 0.200)` |

`SIZE_CHECK Couch > PictureframeMedium = true` is part of the same headless preview run, and the numbers are quoted in `s14`'s `scene_state.size_evidence`.

### Items — KayKit-Restaurant-Bits-1.0

| Committed file | Source path in the repo | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `assets/kaykit/items/fridge_A.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/fridge_A.gltf` | 7062 | `a1835597180f9636dd23669900c1f07fd38813fc5a50685e1d4a7ac1b988ae62` |
| `assets/kaykit/items/fridge_A.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/fridge_A.bin` | 26980 | `58448d94b0c4799586344b2802fdb2c83dbdd80a350778621b0da096c7c77459` |
| `assets/kaykit/items/food_ingredient_bun.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_bun.gltf` | 3071 | `d535883d1395208132a441a264c6bb91f0fb045a4a2bac613ba599fca7ca7c06` |
| `assets/kaykit/items/food_ingredient_bun.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_bun.bin` | 15632 | `a49d342c9dad3f2318798f7dddd72298ea3d364cc76a6440efacd46ffb473fe8` |
| `assets/kaykit/items/food_ingredient_potato.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_potato.gltf` | 3064 | `978e456df24110a4ac9f7469bd24a9e65ecc5a312a0475e34cb2567ce19d8f40` |
| `assets/kaykit/items/food_ingredient_potato.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_potato.bin` | 3496 | `905ad1d4c25e9b6a4b4eb20c994f485cd3a48f72cb1ce94a34fe37ccb49dc182` |
| `assets/kaykit/items/food_ingredient_tomato.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_tomato.gltf` | 3082 | `563c960cbc6a7a0580a75e24e964cab4426fdeda90f602912e57be2fe568c90d` |
| `assets/kaykit/items/food_ingredient_tomato.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_tomato.bin` | 13304 | `82a2319e73119c1dbb9e35eb357b205936bf6f185b9bbf1bf66b5025109925b2` |
| `assets/kaykit/items/food_ingredient_steak.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_steak.gltf` | 3077 | `651a04027439cb47c814db3b943cc28f10f7093e74695214ba86441d212873f3` |
| `assets/kaykit/items/food_ingredient_steak.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_steak.bin` | 13440 | `6196cd9e50e6c2db8fdf0472f0cf031245e898cc4fe98424cfad8b207cedb717` |
| `assets/kaykit/items/restaurantbits_texture.png` | `addons/kaykit_restaurant_bits/Assets/gltf/restaurantbits_texture.png` | 21070 | `1bfff8f880c5e5e1b793bc46fa1f91149b7f70766174a817b3d5962495c5e40f` |
| `assets/kaykit/items/LICENSE.txt` | `LICENSE.txt` | 862 | `4da4ad3a3face68a71c11c8adc8e93017fdeb8fd67fcb0ca8286bd9c3dbbf674` |

Item choice follows the same rule: fridge_A = *der Kühlschrank*, food_ingredient_bun = *das Brötchen*, food_ingredient_potato = *die Kartoffel*, food_ingredient_tomato = *die Tomate*, food_ingredient_steak = *das Fleisch*.

## Vocabulary source

- Goethe-Zertifikat A1 "Start Deutsch 1" Wortliste, section *Alphabetische Wortliste*.
- The page named in Issue #4 (https://www.goethe.de/ins/se/de/m/spr/prf/ueb/pa1.html) answers `HTTP 403` to scripted clients; the official PDF behind it was downloaded instead: https://www.goethe.de/pro/relaunch/prf/de/A1_SD1_Wortliste_02.pdf
- Downloaded copy (kept in ignored `.local/downloads/`, not committed): 712341 bytes, SHA-256 `45fb648bc0ac02338f7898cae065953e320ab72ed0c14e13e0deffe6f1c5d64e`, 29 pages.
- Every lemma in `data/vocabulary/de_a1_starter.json` records the printed entry, the PDF page and the source's own example sentence. The file now holds **47 lemmas**: the 15 PREP-01 delivered (unchanged ids, values and order) plus 32 added by TAV-01 (Issue #8) for the tavern curriculum - 12 verbs, 7 adjectives, 2 prepositions, 1 adverb, 2 expressions and 13 nouns.
- `source_kind` records *how* the source printed the word: `headword`, or `nebeneintrag` / `redewendung` for a word the list prints indented under a headword, in which case `source_parent` names that headword. Only two lemmas are of the second kind: *danke* (page 13, under *danken*) and *„Wie bitte?“* (page 26, under *wie*). No lemma claims to be a headword that the source did not print as one.
- `checked_but_absent` lists everyday words that were looked for and are **not** entries in the A1 list, which is why props such as a chair (*der Stuhl*), a plate (*der Teller*), a bar (*die Theke*), a waiter (*der Kellner*) or a warm/hot/fresh/empty/full adjective are not committed. Near matches are named instead of counted as the same word: *hinten* (17) is an entry, *hinter* is not; *der Herd* (15) appears only inside *die Küche*'s example sentence.
- `reserve_pool` holds 13 further A1 entries verified on a page but deliberately **not** committed as lemmas, each with the reason it is held back (*kaputt, der Preis, die Flasche, das Essen, das Frühstück, mögen, die Karte, bitte, die Entschuldigung, der Moment, „Einen Moment bitte“, Guten Tag, das Restaurant, hinten*). They are a claim about the source, not about the curriculum: none of them is taught until a later task commits it as a lemma.
- The list is a candidate A1 set chosen for a tavern shift, **not** a frequency ranking, and not „the most frequent German words“.
- English and Russian glosses are agent-authored helper translations; the Goethe list itself is monolingual. CI now requires a Cyrillic Russian meaning for **every** lemma, not only for the nouns that have a prop model, because a verb, an adverb or an expression has no object to point at and the hint text is the only place its meaning exists. The glosses still need human review before they can be trusted as teaching.
- Extraction used a throwaway `.local/venv` with `pypdf`; no PDF tooling is committed. TAV-01 re-extracted the same PDF with `extraction_mode="layout"` because the plain pass collapses several pages into one line and therefore cannot show the difference between a headword and an indented *Nebeneintrag*. That re-extraction corrected two pre-existing records rather than loosening the check: *das Brötchen* is printed with an en dash („das Brötchen, –“, and a lone dash in this list marks a plural equal to the lemma) and the Kühlschrank example uses an en dash after the question mark. The 16 absence claims and the 13 reserve entries were re-checked the same way; see `docs/tav01_learning_plan.md`.

## Dialogue plugin smoke

The two-choice reply is proven with the plugin's own balloon, not a custom UI: `tools/prep_dialogue_probe.gd` calls `DialogueManager.show_dialogue_balloon(...)`, asserts the balloon is visible with the German line in its `DialogueLabel` and exactly two visible answer buttons from `ResponsesMenu.get_menu_items()`, then clicks the second button with a real `InputEventMouseButton` pushed through `get_viewport().push_input(...)` and asserts the balloon advanced to the matching branch before `dialogue_ended` fired. That run needs a window (GUI picking is not reliable headless), so it is a short windowed smoke test:

```powershell
& $godot --path . res://scenes/prep_dialogue_smoke.tscn --quit-after 1500 -- --auto
```

Running the same scene without `-- --auto` leaves the balloon open for a human to click.

## Scenario content

Three authored files, 27 records in total, all written for this project and taken from no source, so no third-party licence applies to them:

- `data/scenarios/lex01_starter.json` - 15 records (PREP-01).
- `data/scenarios/lex01_extension.json` - 2 records (LEX-01 delayed retrieval).
- `data/scenarios/tav01_sample_shift.json` - 10 records `t01`...`t10` (TAV-01, Issue #8): six day-1 records that introduce the new corpus words *holen, nehmen, zusammen, kosten, billig, teuer, fertig*, and four day-2 records that revisit four of them in the other camera framing with the staged facts changed. They are a representative subset, not the whole shift: the plan in `docs/tav01_learning_plan.md` records which events and which lemmas wait for TAV-03 props or TAV-04 actions, and why.

Rules in those files are asserted by CI rather than left to the reader:

- `distractor_note` - `distractor_lemma_ids` is the lemmas of the incorrect options minus the lemmas of the correct option; an empty list is valid (s13's and t03's two answers differ only by *ja*/*nein*).
- `presentation_note` - option ids are the authored display slots, the correct answers are spread over `a`/`b`/`c` (starter 5/6/4, sample shift 4/4/2, so 10/11/6 across all 27 records), and LEX-01 must shuffle the visible order at play time so a fixed position can never become the strategy.
- `gloss_note` - every record carries `utterance_gloss_ru` and every `respond` option carries `gloss_ru`, because the translation button has nothing to show otherwise.
- `guided_note` - exactly one first-day `find_select` record carries `guided: true`; that record is the teach-before-test example and is presented first on day 1.
- `decidability_note` (tav01 file) - a corpus lemma becomes a target only when the answer can be worked out from facts the scene presents: which object is staged where (t01, t03, t05, t07, t09, t10), a price stated in the utterance itself (t04, t06), or object identity, which is the basis the committed `bring_deliver` records already use (t02, t08). `deferred_lemma_note` records the lemmas that are *not* targets here and the single thing each one waits for, so a new word is never taught as a guess.

## Interface language and the Cyrillic font

The first human test of LEX-01 (PR #6 review) could not start, because every instruction and control was German while German was the unknown language. The slice now separates the two jobs: **German is the content being learned** (the NPC sentence, the answer sentences and the correct-answer feedback, all from `data/scenarios`), and **Russian is the language that operates the game** (instructions, buttons, status lines, onboarding and summary labels, all from `data/ui/lex01_ui_ru.json`). No gameplay script contains an interface string in either language, and CI asserts that the three gameplay scripts contain neither Cyrillic nor a hard-coded German instruction, so rewording or rebranding the interface is a data change.

That only works if Godot can draw Cyrillic, which was measured instead of assumed:

- `ThemeDB.fallback_font` in Godot 4.7.1 is a built-in `FontFile` (no `res://` path) and reports `has_char` `true` for all 64 probed Cyrillic code points, so **no font asset is committed** and `project.godot` has no `gui/theme/custom_font`.
- The measurement was checked against a control: the same font reports `has_char` `false` for 8 Devanagari and 4 CJK code points, which is what makes the Cyrillic result a real coverage signal rather than a method that always answers yes.
- `tools/lex01_probe.gd` keeps that guard alive: it re-probes the active font for the whole Cyrillic alphabet every run and asserts the labels the player clicks really carry Cyrillic, so a future font or theme change that loses Cyrillic fails the probe instead of silently rendering empty boxes.

This section adds no third-party file; the 27 rows above are still the only third-party files this repository commits.

## Not committed

`.local/` holds the Dialogue Manager archive, the Goethe PDF, the extracted text, the scratch fetch and extraction scripts, the throwaway venv and all Godot run logs; `.godot/` holds import caches. The 27 rows above are the only third-party files this repository commits.
