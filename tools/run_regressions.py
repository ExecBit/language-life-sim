import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

project = Path(__file__).resolve().parents[1]
root = project / '.local' / 'validation'
root.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env['APPDATA'] = str(root / 'GodotUser')
env['LOCALAPPDATA'] = str(root / 'GodotData')
env['XDG_DATA_HOME'] = str(root / 'GodotXdgData')
env['XDG_CONFIG_HOME'] = str(root / 'GodotXdgConfig')
godot = os.environ.get('GODOT') or shutil.which('Godot_v4.7.1-stable_win64_console.exe') or shutil.which('godot')
if not godot:
    raise SystemExit('Godot executable not found')
suites = [
    ('game/test_save_migration.gd', 'SAVE_MIGRATION_NONDESTRUCTIVE_PASS'),
    ('game/communication/test_keyboard_controls.gd', 'MVP_TAB_SELECT_ENTER_SEND_E_OPENER_PASS'),
    ('game/communication/test_speaker_attention.gd', 'MVP_BOUNDED_SPEAKER_ATTENTION_PASS'),

    ('game/communication/test_dialogue_ui.gd', 'MVP_SUBTITLES_E_DIALOGUE_PLAYER_NPC_LOCK_PASS'),
    ('game/communication/test_integration.gd', 'MVP_COMMUNICATION_I01_I11_AUTOMATED_PASS'),
    ('experiments/communication/test_regression.gd', 'COMMUNICATION_SPEC_R01_R15_W01_W07_PASS'),
    ('experiments/communication/test.gd', 'COMMUNICATION_PARSER_CONTEXT_PASS'),
    ('experiments/communication/test_input.gd', 'COMMUNICATION_VIEWPORT_KEYBOARD_WILL_REQUEST_NEGATION_PASS'),
    ('experiments/communication/test_world.gd', 'COMMUNICATION_WORLD_TWO_PATHS_COLLISION_COMPOSER_RESET_PASS'),
    ('experiments/communication/test_pause.gd', 'COMMUNICATION_ESCAPE_MENU_DRAFT_NPC_PAUSE_RESET_PASS'),
    ('game/prologue/test_story.gd', 'REV04_8_STATE_ROUTES_MIGRATION_AND_EVENT_ID_OK'),
    ('game/prologue/test_cooking.gd', 'REV04_COOKING_ALL_OK'),
    ('game/prologue/test_day2_realtime.gd', 'REV04_REALTIME_NO_AUTODIALOGUE_AND_REFUSAL_OK'),
    ('game/prologue/test_walking.gd', 'PROLOGUE_WALK_OK'),
    ('game/shop/test_state.gd', 'SHOP_STATE_TWO_ORDERS_CONTAINER_DELIVERY_UNPACK_OK'),
    ('game/shop/test_world.gd', 'SHOP_WORLD_BUY_RETURN_SAVE_AND_OPTIONAL_UNPACK_OK'),
    ('game/shop/test_bridge.gd', 'SHOP_V4_PROLOGUE_BRIDGE_AND_BACKGROUND_COOKING_OK'),
    ('game/shop/test_restart.gd', 'SHOP_NEW_SCENE_RESTART_PRESERVES_PACKED_DELIVERY_OK'),
    ('game/shop/test_navigation.gd', 'SHOP_WALKABLE_AISLES_COUNTER_AND_WALLS_OK'),
    ('game/settings/test_cogito_settings.gd', 'COGITO_GAME_SETTINGS_PASS'),
]
results = []
for script, marker in suites:
    name = script.replace('/', '_').replace('.gd', '')
    log_path = root / f'attention_regression_{name}.log'
    try:
        proc = subprocess.run([godot, '--headless', '--path', str(project), '--script', 'res://' + script],
                              env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        output = proc.stdout.decode('utf-8', errors='replace')
        passed = proc.returncode == 0 and marker in output and 'SCRIPT ERROR:' not in output
        reason = '' if passed else f'exit={proc.returncode}; expected marker={marker}'
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or b'').decode('utf-8', errors='replace')
        passed = False
        reason = '60-second timeout'
    log_path.write_text(output, encoding='utf-8')
    result = dict(script=script, status='PASS' if passed else 'FAIL', reason=reason, log=str(log_path))
    results.append(result)
    print(f'{script}: {result["status"]} {reason}', flush=True)
(root / 'attention_regression_suites.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Suites: {sum(r["status"] == "PASS" for r in results)}/{len(results)} PASS', flush=True)
sys.exit(1 if any(r['status'] != 'PASS' for r in results) else 0)
