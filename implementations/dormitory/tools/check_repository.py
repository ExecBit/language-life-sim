from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
config = (root / 'project.godot').read_text(encoding='utf-8')
assert 'run/main_scene="res://implementations/dormitory/game/prologue/prologue.tscn"' in config
assert 'uid://' not in config, 'Project startup must not depend on an old UID cache'
for path in ('assets/kaykit', 'addons/dialogue_manager', 'data/vocabulary/de_a1_starter.json'):
    assert not (root / path).exists(), path
for old_folder in ('game', 'experiments', 'docs', 'tools'):
    assert not (root / old_folder).exists(), f'Variant code must not live at repository root: {old_folder}'
for folder in ('implementations/dormitory/game', 'implementations/dormitory/experiments/communication', 'implementations/dormitory/experiments/character_preview'):
    for path in (root / folder).rglob('*'):
        if path.suffix not in ('.gd', '.tscn', '.tres'): continue
        text = path.read_text(encoding='utf-8-sig')
        for reference in re.findall(r'res://[^"\s)]+', text):
            if reference.endswith(('.gd', '.tscn', '.tres', '.fbx', '.glb', '.vrm', '.svg')):
                if reference in ('res://assets/characters/private/astera.vrm', 'res://implementations/dormitory/game/shop/Assets/vendor.vrm'): continue
                assert (root / reference[6:]).is_file(), (path, reference)
        assert 'res://LanguageLife' not in text, path
# Reject stale runtime resource references to the former root-level folders.
for folder in ('implementations/dormitory/game', 'implementations/dormitory/experiments'):
    for path in (root / folder).rglob('*'):
        if path.suffix in ('.gd', '.tscn', '.tres', '.import', '.md'):
            text = path.read_text(encoding='utf-8-sig')
            assert 'res://game/' not in text and 'res://experiments/' not in text, path
# Check that old variant-owned files have moved with their documentation and tests.
for required in (
    'implementations/dormitory/docs/GAME_CONCEPT.md',
    'implementations/dormitory/docs/PROLOGUE_DAYS_01_02.md',
    'implementations/dormitory/tools/run_regressions.py',
    'implementations/dormitory/README.md',
    'assets/PROVENANCE.md',
):
    assert (root / required).is_file(), required

# Local Markdown links in the moved variant docs and the entry READMEs must resolve.
for root_doc in (root / 'README.md', root / 'implementations/README.md',
                 root / 'implementations/dormitory/README.md'):
    for link in re.findall(r'\]\(([^)]+)\)', root_doc.read_text(encoding='utf-8')):
        target = link.split('#', 1)[0]
        if target and not re.match(r'^[a-z]+://', target):
            assert (root_doc.parent / target).exists(), (root_doc, link)
for path in (root / 'implementations/dormitory/docs').rglob('*.md'):
    for link in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
        target = link.split('#', 1)[0]
        if target and not re.match(r'^[a-z]+://', target):
            assert (path.parent / target).exists(), (path, link)

# Variant-specific runtime files must not import another implementation.
for path in (root / 'implementations/dormitory').rglob('*'):
    if path.suffix in ('.gd', '.tscn', '.tres', '.import'):
        data = path.read_text(encoding='utf-8-sig')
        for target in re.findall(r'res://implementations/([^/]+)/', data):
            assert target == 'dormitory', (path, target)

for folder in ('cogito', 'vrm', 'mtoon', 'godot_state_charts', 'input_helper', 'quick_audio'):
    assert (root / 'addons' / folder / 'plugin.cfg').is_file(), folder
print('MIGRATION_STRUCTURE_PASS')
