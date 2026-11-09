from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
config = (root / 'project.godot').read_text(encoding='utf-8')
assert 'run/main_scene="res://game/prologue/prologue.tscn"' in config
assert 'uid://' not in config, 'Project startup must not depend on an old UID cache'
for path in ('assets/kaykit', 'addons/dialogue_manager', 'data/vocabulary/de_a1_starter.json'):
    assert not (root / path).exists(), path
for folder in ('game', 'experiments/communication', 'experiments/character_preview'):
    for path in (root / folder).rglob('*'):
        if path.suffix not in ('.gd', '.tscn', '.tres'): continue
        text = path.read_text(encoding='utf-8-sig')
        for reference in re.findall(r'res://[^"\s)]+', text):
            if reference.endswith(('.gd', '.tscn', '.tres', '.fbx', '.glb', '.vrm', '.svg')):
                if reference in ('res://assets/characters/private/astera.vrm', 'res://game/shop/Assets/vendor.vrm'): continue
                assert (root / reference[6:]).is_file(), (path, reference)
        assert 'res://LanguageLife' not in text, path
for folder in ('cogito', 'vrm', 'mtoon', 'godot_state_charts', 'input_helper', 'quick_audio'):
    assert (root / 'addons' / folder / 'plugin.cfg').is_file(), folder
print('MIGRATION_STRUCTURE_PASS')
