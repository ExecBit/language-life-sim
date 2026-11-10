# Language Life Sim

Godot 4.7.1 project. The playable entry point is the prologue / LEVEL_01, followed by the existing LEVEL_02 shop.

Open this repository's `project.godot`, allow imports to finish, and press **F5**. The initial screen offers a new game and continuing an existing save.

## Controls

- WASD / mouse: move and look; E: interact or open an NPC conversation.
- In conversation: type a phrase or word prefix, arrows select a suggestion, Tab inserts it, Enter sends the phrase. E opening the conversation is not inserted into the input.
- H: word helper in world mode; click the helper button while typing. Esc: close helper, then pause. Conversation locks player movement.
- NPC speech outside a conversation uses temporary subtitles. NPC attention is bounded rather than permanently following the player.

## Structure

| Directory | Responsibility |
| --- | --- |
| `game/prologue/` | Main entry, LEVEL_01, house, story, UI and state |
| `game/shop/` | Existing LEVEL_02 and shopping state |
| `game/communication/` | Shared parser, vocabulary, composer, helper and dialogue integration |
| `game/characters/` | Project-owned model adapters and animation retargeting |
| `assets/animations/motifect/` | Animation packs, with their license notices |
| `assets/characters/` | Redistributable sample model and optional local model |
| `addons/` | Cogito and other third-party dependencies; variant-specific code stays in its own `implementations/<variant>/` |
| `experiments/communication/` | Independent locked-room experiment |
| `experiments/character_preview/` | Legacy character/animation preview, F7 animation browser |
| `docs/` | Variant-specific design documents, including the historical archive at `docs/archive/` |

Runtime autoloads are declared explicitly in `project.godot`. Cogito, Input Helper and Quick Audio editor plugins are disabled to avoid re-registering those singletons during a first import; their runtime code remains active. VRM/MToon import plugins and State Charts remain enabled.

Run the experiment or preview with F6 on its `.tscn`. They do not replace the F5 entry point.

## Граница вариантов

The existing gameplay, dialogue parser, state, characters, shop, and prototypes belong to `implementations/dormitory/`. New implementations use separate `implementations/<variant>/` folders, including their own gameplay code, scenarios, state, vocabulary and tests. Implementations must not import one another.

Only engine extensions (`addons/`) and reusable models/animations (`assets/`) are shared across variants. `project.godot` is a common Godot root and currently starts the dormitory implementation with F5; open another implementation's entry scene directly with F6. Runtime save files must have distinct names per implementation. Do not reuse the dormitory's save keys for other settings.

## Models and saves

Astera prohibits redistribution in its embedded metadata and is not committed. An existing local copy lives in ignored `assets/characters/private/astera.vrm`. Without it, Lena uses the included VRoid sample model. Reimport after adding a model. See [asset provenance](../../assets/PROVENANCE.md).

Saves use the stable custom Godot directory `Language Life Sim`. On Windows this is `%APPDATA%/Language Life Sim`. On first launch, missing session/settings files are copied from `%APPDATA%/Godot/app_userdata/Cogito`; existing destination files and original files are preserved. The old tavern save is unrelated and is not imported.

## Verification

```powershell
python implementations/dormitory/tools/check_repository.py
Godot_v4.7.1-stable_win64_console.exe --headless --path . --editor --import
python implementations/dormitory/tools/run_regressions.py
```

`GODOT` can specify another Godot 4.7.1 executable. Tests isolate user data and write logs to ignored `.local/validation/`. CI runs structural checks, a clean import and the migrated regression suite.

Manual review: start a new game, meet Lena, exchange greetings with E/Tab/Enter, close the conversation and walk; take/place items, sleep, complete or decline the morning request, leave for the shop, buy and return home. Pause and reload during both levels. Check idle/walking, subtitles and that the NPC stops tracking after speaking. Also open the communication experiment and exercise both door solutions.

The source migration is from Cogito project commit `533e773e`; Cogito's MIT notice is in `addons/cogito/LICENSE`. This move does not establish language-learning effectiveness; a beginner playtest is still required.
