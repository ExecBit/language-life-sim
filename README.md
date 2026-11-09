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
| `addons/` | Cogito and other third-party dependencies; game code stays in `game/` |
| `experiments/communication/` | Independent locked-room experiment |
| `experiments/character_preview/` | Legacy character/animation preview, F7 animation browser |
| `docs/` | Product requirements; historical tavern documents in `docs/archive/` |

Runtime autoloads are declared explicitly in `project.godot`. Cogito, Input Helper and Quick Audio editor plugins are disabled to avoid re-registering those singletons during a first import; their runtime code remains active. VRM/MToon import plugins and State Charts remain enabled.

Run the experiment or preview with F6 on its `.tscn`. They do not replace the F5 entry point.

## Models and saves

Astera prohibits redistribution in its embedded metadata and is not committed. An existing local copy lives in ignored `assets/characters/private/astera.vrm`. Without it, Lena uses the included VRoid sample model. Reimport after adding a model. See [asset provenance](docs/assets_provenance.md).

Saves use the stable custom Godot directory `Language Life Sim`. On Windows this is `%APPDATA%/Language Life Sim`. On first launch, missing session/settings files are copied from `%APPDATA%/Godot/app_userdata/Cogito`; existing destination files and original files are preserved. The old tavern save is unrelated and is not imported.

## Verification

```powershell
python tools/check_repository.py
Godot_v4.7.1-stable_win64_console.exe --headless --path . --editor --import
python tools/run_regressions.py
```

`GODOT` can specify another Godot 4.7.1 executable. Tests isolate user data and write logs to ignored `.local/validation/`. CI runs structural checks, a clean import and the migrated regression suite.

Manual review: start a new game, meet Lena, exchange greetings with E/Tab/Enter, close the conversation and walk; take/place items, sleep, complete or decline the morning request, leave for the shop, buy and return home. Pause and reload during both levels. Check idle/walking, subtitles and that the NPC stops tracking after speaking. Also open the communication experiment and exercise both door solutions.

The source migration is from Cogito project commit `533e773e`; Cogito's MIT notice is in `addons/cogito/LICENSE`. This move does not establish language-learning effectiveness; a beginner playtest is still required.

## Settings

Open **Настройки** from the main menu or Esc pause menu. This embeds Cogito's existing options scene with project adapters under `game/settings/`; vendor code is unchanged. Gameplay (invert Y, mouse/gamepad sensitivity, headbob, crouch toggle), graphics (windowed resolution, fullscreen/render scale, VSync, 2D/3D AA, GUI scale), audio (music/SFX) and movement bindings are available. Reserved interaction/dialogue keys remain E/Tab/Enter/Esc. Project master volume and text size are retained below the tabs.

**Применить** saves changes without closing; **Сохранить и назад** or Esc saves and returns to the screen that opened settings. Esc first cancels an active key capture. During play, settings keep the world paused until **Продолжить**. Settings persist in `user://options.cfg`; project master volume/text size stay in `language_life_prologue_settings.cfg`. Missing Cogito `options.cfg` is also copied from the original Cogito user directory without overwriting an existing one. Legacy mouse sensitivity is imported only when no Cogito options file exists.

Settings regression: `Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://game/settings/test_cogito_settings.gd`. For visual review, run the same command without `--headless` in an isolated user-data environment: it checks actual 1280x720 window size and writes screenshots to `user://cogito_settings_*.png`. Manually change invert Y, apply/resume, look up/down, reopen settings, switch fullscreen/window resolution and restart to confirm persistence.
