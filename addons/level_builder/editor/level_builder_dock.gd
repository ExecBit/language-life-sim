@tool
extends Control

# Level Builder dock. Five tabs (Setup / Generate / Layers / Colliders / Assets)
# and the north-star footer: Check Level + Test Walk, visible from every tab.
#
# All the real work lives in the editor/*.gd logic modules — this file is UI
# and editor glue only. It must stay instantiable OUTSIDE the editor (headless
# verify builds it), so: no EditorInterface in _ready, dialogs created lazily
# in button handlers, thumbnails only behind Engine.is_editor_hint().

const BOOTSTRAP := preload("res://addons/level_builder/editor/scene_bootstrap.gd")
const LAYER_TOOLS := preload("res://addons/level_builder/editor/layer_tools.gd")
const COLLIDER_TOOLS := preload("res://addons/level_builder/editor/collider_tools.gd")
const LEVEL_CHECK := preload("res://addons/level_builder/editor/level_check.gd")
const LAUNCHER := preload("res://addons/level_builder/editor/playtest_launcher.gd")
const PALETTE := preload("res://addons/level_builder/editor/asset_palette.gd")
const PREFS := preload("res://addons/level_builder/editor/lb_prefs.gd")
const GENERATOR := preload("res://addons/level_builder/generator/generator.gd")
const GEN_LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")
const GEN_TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const GEN_SCENE := preload("res://addons/level_builder/generator/gen_scene.gd")
const SPACE_SCANNER := preload("res://addons/level_builder/generator/space_scanner.gd")
const GEN_DEBUG := preload("res://addons/level_builder/generator/gen_debug.gd")
const BRIEF := preload("res://addons/level_builder/resources/generation_brief.gd")

# tools/build_lite.gd writes this into the cut-down package; the full pack has
# no such file, so the tier line below simply never appears.
const LITE_MARKER := "res://addons/level_builder/LITE"

const DIM := Color(0.72, 0.74, 0.78)
const RED := Color(0.92, 0.33, 0.33)
const AMBER := Color(0.95, 0.80, 0.35)
const GREEN := Color(0.29, 0.82, 0.47)

# both set by plugin.gd right after new(), before add_control_to_dock
var undo_redo  # EditorUndoRedoManager
var placement  # placement_controller.gd instance (shared with the plugin's input forwarding)

var _body: VBoxContainer
var _tabs: TabContainer
var _check_button: Button
var _walk_button: Button

# Setup tab
var _preset_option: OptionButton
var _ground_check: CheckBox
var _nav_check: CheckBox
var _audit_results: VBoxContainer
var _new_level_dialog: EditorFileDialog

# Generate tab
var _scope_option: OptionButton
var _brief_option: OptionButton
var _gen_size_option: OptionButton
var _seed_spin: SpinBox
var _interiors_check: CheckBox
var _terrain_check: CheckBox
var _gen_status: Label
var _gen_results: VBoxContainer
var _units_box: VBoxContainer
var _zones_check: CheckBox
var _palette_option: OptionButton
var _density_slider: HSlider
var _openness_slider: HSlider
var _branching_slider: HSlider
var _fill_arch_option: OptionButton
var _briefs: Array[Resource] = []

# Layers tab
var _layer_status: Label
var _names_confirm: ConfirmationDialog

# Colliders tab
var _policy_option: OptionButton
var _collider_role_option: OptionButton
var _skip_existing_check: CheckBox
var _collider_status: Label
var _layer_profiles: Array[Resource] = []

# Assets tab
var _folder_list: ItemList
var _search_edit: LineEdit
var _category_option: OptionButton
var _asset_list: ItemList
var _place_status: Label
var _entries: Array[Dictionary] = []
var _folder_dialog: EditorFileDialog

# Footer dialogs
var _check_dialog: AcceptDialog
var _check_rows: VBoxContainer
var _walk_confirm: ConfirmationDialog
var _save_first: AcceptDialog


# Drag source for the native path: dropping onto the 3D viewport uses the
# editor's own "files" drop handling, so it behaves exactly like a drag from
# the FileSystem dock.
class PaletteList extends ItemList:
	func _get_drag_data(at_position: Vector2) -> Variant:
		var idx := get_item_at_position(at_position, true)
		if idx < 0:
			return null
		var meta: Dictionary = get_item_metadata(idx)
		var label := Label.new()
		label.text = get_item_text(idx)
		set_drag_preview(label)
		return {"type": "files", "files": [String(meta["path"])]}


func _ready() -> void:
	name = "Level Builder"
	_build_ui()
	_refresh_assets()
	# Lists of files keep up with files added this session: when their tab opens,
	# and when the project's files change. Guarded, so headless builds still work.
	_brief_option.visibility_changed.connect(_on_generate_shown)
	_asset_list.visibility_changed.connect(_on_assets_shown)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_files_changed)


# A plain Control doesn't tell the dock slot how small the tabs and footer can go,
# so say it here. Each tab's page scrolls, so this stays short.
func _get_minimum_size() -> Vector2:
	if _body == null:
		return Vector2.ZERO
	return _body.get_combined_minimum_size()


func _on_generate_shown() -> void:
	if _brief_option.is_visible_in_tree():
		_refresh_library()


func _on_assets_shown() -> void:
	if _asset_list.is_visible_in_tree():
		_refresh_assets_if_changed()


func _on_files_changed() -> void:
	_on_generate_shown()
	_on_assets_shown()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.minimum_size_changed.connect(update_minimum_size)
	add_child(root)
	_body = root

	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_build_setup_tab()
	_build_generate_tab()
	_build_layers_tab()
	_build_colliders_tab()
	_build_assets_tab()

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 6)
	root.add_child(footer)

	_check_button = Button.new()
	_check_button.name = "CheckLevelButton"
	_check_button.text = "Check Level"
	_check_button.tooltip_text = "Playability checklist for the open scene."
	_check_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_check_button.pressed.connect(_on_check_level)
	footer.add_child(_check_button)

	_walk_button = Button.new()
	_walk_button.name = "TestWalkButton"
	_walk_button.text = "Test Walk"
	_walk_button.tooltip_text = "Save the scene, then walk it with the bundled test player."
	_walk_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_walk_button.pressed.connect(_on_test_walk)
	footer.add_child(_walk_button)

	# long labels on full-width buttons and ticks wrap instead of widening the dock
	for scroll in _tabs.get_children():
		for c in scroll.get_child(0).get_children():
			if c is Button and not (c is OptionButton):
				(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# The scroll is the tab (its name is the title) and the page scrolls inside it,
# so a tall page like Generate never pushes Check Level and Test Walk off the
# bottom of the screen.
func _tab_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.name = title + "Page"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6)
	scroll.add_child(page)
	return page


func _section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", DIM)
	parent.add_child(label)


# ---------------------------------------------------------------------------
# Setup tab
# ---------------------------------------------------------------------------

func _build_setup_tab() -> void:
	var page := _tab_page("Setup")

	_section_label(page, "New level")
	_preset_option = OptionButton.new()
	for preset_name in BOOTSTRAP.preset_names():
		_preset_option.add_item(preset_name)
	page.add_child(_preset_option)

	_ground_check = CheckBox.new()
	_ground_check.text = "Ground plane (60 m, collides)"
	_ground_check.button_pressed = true
	page.add_child(_ground_check)

	_nav_check = CheckBox.new()
	_nav_check.text = "NavigationRegion3D (for AI later)"
	page.add_child(_nav_check)

	var new_button := Button.new()
	new_button.text = "New 3D Level…"
	new_button.pressed.connect(_on_new_level)
	page.add_child(new_button)

	page.add_child(HSeparator.new())
	_section_label(page, "Existing scene")
	var audit_button := Button.new()
	audit_button.text = "Audit Open Scene"
	audit_button.pressed.connect(_on_audit_scene)
	page.add_child(audit_button)

	# the findings grow the page, which scrolls, rather than a box of their own
	# that a short dock squeezes to nothing
	_audit_results = VBoxContainer.new()
	_audit_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_audit_results)


func _selected_preset() -> String:
	return _preset_option.get_item_text(_preset_option.selected)


# The scope the user picked, as a Scope enum value — not the dropdown index.
func _selected_scope() -> int:
	if _scope_option == null or _scope_option.selected < 0:
		return BRIEF.Scope.ROOM
	return int(_scope_option.get_item_metadata(_scope_option.selected))


func _on_new_level() -> void:
	if _new_level_dialog == null:
		_new_level_dialog = EditorFileDialog.new()
		_new_level_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_new_level_dialog.add_filter("*.tscn", "Scene")
		_new_level_dialog.current_dir = "res://"
		_new_level_dialog.file_selected.connect(_on_new_level_path)
		add_child(_new_level_dialog)
	_new_level_dialog.current_file = "level.tscn"
	_new_level_dialog.popup_centered_ratio(0.5)


func _on_new_level_path(path: String) -> void:
	var skeleton: Node3D = BOOTSTRAP.build_skeleton(
		_selected_preset(), _ground_check.button_pressed, _nav_check.button_pressed)
	var packed := PackedScene.new()
	if packed.pack(skeleton) != OK or ResourceSaver.save(packed, path) != OK:
		skeleton.free()
		push_error("Level Builder: couldn't save " + path)
		return
	skeleton.free()
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)


func _edited_root() -> Node:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_edited_scene_root()


func _on_audit_scene() -> void:
	var root := _edited_root()
	if root == null:
		_render_findings(_audit_results, [], "Open a scene first.")
		return
	var findings: Array[Dictionary] = BOOTSTRAP.audit(root)
	_render_findings(_audit_results, findings, "Scene looks good — bootstrap-wise.")


func _render_findings(into: VBoxContainer, findings: Array[Dictionary], empty_message: String) -> void:
	for child in into.get_children():
		child.queue_free()
	if findings.is_empty():
		var ok_label := Label.new()
		ok_label.text = empty_message
		ok_label.add_theme_color_override("font_color", GREEN)
		ok_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		into.add_child(ok_label)
		return
	for finding in findings:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		into.add_child(row)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", RED if String(finding["severity"]) == "red" else AMBER)
		row.add_child(dot)
		var msg := Label.new()
		msg.text = String(finding["message"])
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(msg)
		if bool(finding.get("fixable", false)):
			var fix := Button.new()
			fix.text = "Fix"
			var fix_id := String(finding["id"])
			fix.pressed.connect(_on_fix.bind(fix_id, into))
			row.add_child(fix)


func _on_fix(fix_id: String, results_box: VBoxContainer) -> void:
	var root := _edited_root()
	if root == null:
		return
	if undo_redo:
		undo_redo.create_action("Level Builder: fix " + fix_id)
		if not BOOTSTRAP.apply_fix(fix_id, root, _selected_preset(), undo_redo):
			LEVEL_CHECK.apply_fix(fix_id, root, undo_redo)
		undo_redo.commit_action()
	else:
		if not BOOTSTRAP.apply_fix(fix_id, root, _selected_preset(), null):
			LEVEL_CHECK.apply_fix(fix_id, root, null)
	# re-run whichever list the fix came from
	if results_box == _audit_results:
		_on_audit_scene()
	else:
		_on_check_level()


# ---------------------------------------------------------------------------
# Generate tab
# ---------------------------------------------------------------------------

func _build_generate_tab() -> void:
	var page := _tab_page("Generate")

	_section_label(page, "Scope")
	_scope_option = OptionButton.new()
	_scope_option.name = "ScopeOption"
	# Only scopes with presets behind them. The scope id rides on the item rather
	# than being its index, because the list is no longer the whole enum.
	for scope in GEN_LIBRARY.scopes_with_briefs():
		var scope_index := _scope_option.item_count
		_scope_option.add_item(GEN_TYPES.SCOPE_NAMES[scope])
		_scope_option.set_item_metadata(scope_index, scope)
	_scope_option.tooltip_text = "Room: one furnished space. Level: a building of rooms and corridors. World: terrain, roads and points of interest."
	_scope_option.item_selected.connect(func(_i: int) -> void: _refresh_briefs())
	page.add_child(_scope_option)

	_section_label(page, "Preset")
	_brief_option = OptionButton.new()
	_brief_option.name = "BriefOption"
	page.add_child(_brief_option)

	_section_label(page, "What kind of place")
	_density_slider = _knob(page, "Bare", "Crammed", "How full the spaces come out.")
	_openness_slider = _knob(page, "Tight", "Open", "Small cellular spaces, or big sprawling ones.")
	_branching_slider = _knob(page, "One route", "Warren", "A route through, or somewhere to get lost in.")

	_palette_option = OptionButton.new()
	_palette_option.name = "PaletteOption"
	_palette_option.tooltip_text = "Who lives here and how well they keep it. Same floor plan, different place."
	for palette in GEN_LIBRARY.palettes():
		_palette_option.add_item(String(palette.display_name))
	page.add_child(_palette_option)

	_gen_size_option = OptionButton.new()
	for size_name in GEN_TYPES.SIZE_NAMES:
		_gen_size_option.add_item(size_name)
	_gen_size_option.selected = 1
	page.add_child(_gen_size_option)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	page.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.add_theme_color_override("font_color", DIM)
	seed_row.add_child(seed_label)
	_seed_spin = SpinBox.new()
	_seed_spin.name = "SeedSpin"
	_seed_spin.min_value = 0
	_seed_spin.max_value = 2147483647
	_seed_spin.step = 1
	_seed_spin.value = 1
	_seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_spin.tooltip_text = "Same seed and settings always give the same result. A bug report is a seed."
	seed_row.add_child(_seed_spin)
	var reroll := _dice_button()
	reroll.tooltip_text = "Roll a new seed."
	reroll.pressed.connect(func() -> void: _seed_spin.value = randi() % 2147483647)
	seed_row.add_child(reroll)

	_interiors_check = CheckBox.new()
	_interiors_check.text = "Fill POI interiors now"
	_interiors_check.tooltip_text = "Off leaves movable POI markers you can reposition before committing to a building."
	_interiors_check.button_pressed = true
	page.add_child(_interiors_check)

	_terrain_check = CheckBox.new()
	_terrain_check.text = "Replace the ground plane with terrain"
	_terrain_check.tooltip_text = "World scope builds terrain to fit the map. The 60 m bootstrap ground goes away — undo brings it back."
	_terrain_check.button_pressed = true
	page.add_child(_terrain_check)

	var generate_button := Button.new()
	generate_button.name = "GenerateButton"
	generate_button.text = "Generate"
	generate_button.tooltip_text = "Plans, builds, furnishes and validates — as one undo step."
	generate_button.pressed.connect(_on_generate)
	page.add_child(generate_button)

	_gen_status = Label.new()
	_gen_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gen_status.add_theme_color_override("font_color", DIM)
	_gen_status.text = "Pick a scope and a preset, then Generate. Check Level and Test Walk work on the result like anything else you build."
	page.add_child(_gen_status)

	if FileAccess.file_exists(LITE_MARKER):
		var tier := Label.new()
		tier.name = "TierNote"
		tier.text = "Room scope. Buildings and regions are in the full version."
		tier.add_theme_color_override("font_color", DIM)
		tier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tier.tooltip_text = "demo/showcase_walk.tscn (F6) is real output from the full version — walk through it."
		page.add_child(tier)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 64)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_gen_results = VBoxContainer.new()
	_gen_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gen_results)

	_zones_check = CheckBox.new()
	_zones_check.name = "ShowZonesCheck"
	_zones_check.text = "Show zones and walking lanes"
	_zones_check.tooltip_text = "Colours every cell by what the generator thinks it's for. A preview only — it can never be saved into your scene."
	_zones_check.toggled.connect(_on_show_zones)
	page.add_child(_zones_check)

	page.add_child(HSeparator.new())
	_section_label(page, "Fill a space you built yourself")
	_fill_arch_option = OptionButton.new()
	_fill_arch_option.name = "FillArchetypeOption"
	for arch in GEN_LIBRARY.room_archetypes():
		_fill_arch_option.add_item(String(arch.display_name))
	page.add_child(_fill_arch_option)
	var fill_button := Button.new()
	fill_button.name = "FillSelectionButton"
	fill_button.text = "Fill Selection"
	fill_button.tooltip_text = "Select the room you built, then this reads your walls and furnishes inside them. Only the space you selected is touched."
	fill_button.pressed.connect(_on_fill_selection)
	page.add_child(fill_button)

	page.add_child(HSeparator.new())
	var units_header := HBoxContainer.new()
	page.add_child(units_header)
	var units_label := Label.new()
	units_label.text = "Lock what you want kept"
	units_label.tooltip_text = "Locked units survive regeneration exactly as they are. Corridors leading to a locked room are kept with it."
	units_label.add_theme_color_override("font_color", DIM)
	units_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	units_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	units_header.add_child(units_label)
	var refresh_units := Button.new()
	refresh_units.text = "Refresh"
	refresh_units.pressed.connect(_refresh_units)
	units_header.add_child(refresh_units)

	# The list grows the page, which scrolls. In a box of its own at the bottom of a
	# page taller than the dock it got squeezed to nothing.
	_units_box = VBoxContainer.new()
	_units_box.name = "UnitsBox"
	_units_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_units_box)

	_refresh_briefs()
	_refresh_units()


# The editor font has no emoji, so the dice emoji these used to show drew as an empty box.
# The editor's own dice icon instead, and a word where there's no editor theme.
func _dice_button() -> Button:
	var b := Button.new()
	b.text = "Roll"
	if Engine.is_editor_hint():
		var ed_theme := EditorInterface.get_editor_theme()
		if ed_theme != null and ed_theme.has_icon("RandomNumberGenerator", "EditorIcons"):
			b.icon = ed_theme.get_icon("RandomNumberGenerator", "EditorIcons")
			b.text = ""
	return b


# A labelled slider: the ends say what the extremes mean, because "0.8 density"
# tells you nothing and "nearly crammed" does.
func _knob(page: Control, low: String, high: String, tip: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	page.add_child(row)
	var left := Label.new()
	left.text = low
	left.add_theme_color_override("font_color", DIM)
	row.add_child(left)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = 0.5
	slider.tooltip_text = tip
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var right := Label.new()
	right.text = high
	right.add_theme_color_override("font_color", DIM)
	row.add_child(right)
	return slider


func _refresh_briefs() -> void:
	GEN_LIBRARY.refresh()  # pick up .tres the user just added
	var previous := _brief_option.get_item_text(_brief_option.selected) if _brief_option.selected >= 0 else ""
	_briefs = GEN_LIBRARY.briefs_for_scope(_selected_scope())
	_brief_option.clear()
	for brief in _briefs:
		var idx := _brief_option.item_count
		_brief_option.add_item(String(brief.brief_name))
		if String(brief.brief_name) == previous:
			_brief_option.selected = idx
	var is_world := _selected_scope() == BRIEF.Scope.WORLD
	_interiors_check.visible = is_world
	_terrain_check.visible = is_world


# A preset, style or room type added this session (a .tres dropped into
# defaults/generation) is offered without rebuilding the dock. Each dropdown keeps
# its pick, and the style and room lists stay in step with the library, which
# Generate and Fill Selection read by position.
func _refresh_library() -> void:
	_refresh_briefs()
	_refill_names(_palette_option, GEN_LIBRARY.palettes())
	_refill_names(_fill_arch_option, GEN_LIBRARY.room_archetypes())


func _refill_names(option: OptionButton, items: Array[Resource]) -> void:
	var keep: String = option.get_item_text(option.selected) if option.selected >= 0 else ""
	option.clear()
	for item in items:
		option.add_item(String(item.display_name))
		if String(item.display_name) == keep:
			option.select(option.item_count - 1)


func _on_generate() -> void:
	var root := _edited_root()
	if root == null:
		_gen_status.text = "Open a scene first — Setup tab builds one in a click."
		return
	_refresh_library()  # a .tres added since the tab was built should just work
	if _briefs.is_empty() or _brief_option.selected < 0:
		_gen_status.text = "No presets for this scope. Add a brief_*.tres in addons/level_builder/defaults/generation/."
		return

	var brief: Resource = _briefs[_brief_option.selected].duplicate()
	brief.size_class = _gen_size_option.selected
	brief.rng_seed = int(_seed_spin.value)
	var palettes := GEN_LIBRARY.palettes()
	if _palette_option.selected >= 0 and _palette_option.selected < palettes.size():
		brief.palette_id = String(palettes[_palette_option.selected].palette_id)
	brief.generate_interiors = _interiors_check.button_pressed
	brief.density = _density_slider.value
	brief.openness = _openness_slider.value
	brief.branching = _branching_slider.value

	var result: Dictionary = GENERATOR.generate(brief)
	if not result["ok"]:
		GENERATOR.discard(result)
		_gen_status.text = "Nothing applied — the plan didn't validate. Try another seed."
		_render_findings(_gen_results, result["findings"], "")
		return

	if undo_redo:
		undo_redo.create_action("Level Builder: generate %s" % GEN_TYPES.SCOPE_NAMES[int(brief.scope)])
		GENERATOR.apply(result, root, undo_redo, _terrain_check.button_pressed)
		undo_redo.commit_action()
	else:
		GENERATOR.apply(result, root, null, _terrain_check.button_pressed)

	var stats: Dictionary = result["stats"]
	_gen_status.text = "%s (%s), seed %d: %d units, %d props, %.0f ms. One undo step — press Test Walk." % [
		String(brief.brief_name), _palette_option.get_item_text(maxi(0, _palette_option.selected)),
		int(brief.rng_seed), int(stats["units"]), int(stats["props"]), float(stats["msec"])]
	_render_findings(_gen_results, result["findings"],
		"Validated: anchors placed, walking lanes clear, nothing overlapping, every unit reachable.")
	_refresh_units()
	if _zones_check.button_pressed:
		GEN_DEBUG.build(root)  # keep the overlay honest about what's there now


# ---------------------------------------------------------------------------
# Generate tab: locks, per-unit re-roll, fill selection
# ---------------------------------------------------------------------------

func _refresh_units() -> void:
	if _units_box == null:
		return
	for child in _units_box.get_children():
		child.queue_free()
	var root := _edited_root()
	var units: Array[Dictionary] = GEN_SCENE.read_units(root) if root else ([] as Array[Dictionary])
	if units.is_empty():
		var empty := Label.new()
		empty.text = "Nothing generated in this scene yet."
		empty.add_theme_color_override("font_color", DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_units_box.add_child(empty)
		return
	var locked_count := 0
	for unit in units:
		var kind := String(unit["kind"])
		# corridors and roads aren't locked on their own — a corridor is kept
		# with the room it serves, and roads are redrawn for free
		if kind == "corridor" or kind == "road":
			continue
		var unit_id := String(unit["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_units_box.add_child(row)

		var lock := CheckBox.new()
		lock.button_pressed = bool(unit["locked"])
		lock.tooltip_text = "Keep %s exactly as it is when you regenerate." % unit_id
		lock.toggled.connect(_on_lock_toggled.bind(unit_id))
		row.add_child(lock)
		if bool(unit["locked"]):
			locked_count += 1

		var label := Label.new()
		label.text = "%s — %s" % [unit_id, unit["type"] if String(unit["type"]) != "" else kind]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)

		var reroll := _dice_button()
		reroll.disabled = not (kind == "room" or kind == "scan")
		reroll.tooltip_text = "Re-roll just this room's furniture. Nothing else in the scene moves." \
			if not reroll.disabled else "Only rooms carry furniture."
		reroll.pressed.connect(_on_reroll_unit.bind(unit_id))
		row.add_child(reroll)
	if locked_count > 0:
		var pinned := GEN_SCENE.pinned_units(root).size()
		var note := Label.new()
		note.text = "%d locked, %d unit(s) held in place." % [locked_count, pinned]
		note.add_theme_color_override("font_color", DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_units_box.add_child(note)


func _on_show_zones(pressed: bool) -> void:
	var root := _edited_root()
	if root == null:
		_gen_status.text = "Open a scene first."
		return
	if not pressed:
		GEN_DEBUG.clear(root)
		return
	var mapped := GEN_DEBUG.build(root)
	_gen_status.text = "Zones shown for %d room(s). Blue is circulation, orange is the work zone, purple is storage, yellow is what you're meant to look at." % mapped \
		if mapped > 0 else "Nothing generated in this scene to show zones for."


func _on_lock_toggled(pressed: bool, unit_id: String) -> void:
	var root := _edited_root()
	if root == null:
		return
	if undo_redo:
		undo_redo.create_action("Level Builder: %s %s" % ["lock" if pressed else "unlock", unit_id])
		GEN_SCENE.set_locked(root, unit_id, pressed, undo_redo)
		undo_redo.commit_action()
	else:
		GEN_SCENE.set_locked(root, unit_id, pressed, null)
	_refresh_units()


func _on_reroll_unit(unit_id: String) -> void:
	var root := _edited_root()
	if root == null:
		return
	var seed_value := randi() % 2147483647
	var result := {}
	if undo_redo:
		undo_redo.create_action("Level Builder: re-roll " + unit_id)
		result = GENERATOR.regenerate_unit(root, unit_id, seed_value, undo_redo)
		undo_redo.commit_action()
	else:
		result = GENERATOR.regenerate_unit(root, unit_id, seed_value, null)
	_gen_status.text = String(result.get("message", "Nothing happened."))


func _on_fill_selection() -> void:
	var root := _edited_root()
	if root == null:
		_gen_status.text = "Open a scene first."
		return
	_refresh_library()  # the room list and the library it indexes stay in step
	var archetypes := GEN_LIBRARY.room_archetypes()
	if archetypes.is_empty() or _fill_arch_option.selected < 0:
		_gen_status.text = "No room archetypes to fill with."
		return
	var bounds := AABB()
	var started := false
	for node in _selection():
		if not (node is Node3D):
			continue
		var node_box: AABB = SPACE_SCANNER.node_bounds(node)
		if node_box.size == Vector3.ZERO:
			continue
		bounds = node_box if not started else bounds.merge(node_box)
		started = true
	if not started:
		_gen_status.text = "Select the room you want furnished — the walls and floor you built, not an empty node."
		return

	var archetype_id := String(archetypes[_fill_arch_option.selected].archetype_id)
	var seed_value := int(_seed_spin.value)
	var result := {}
	if undo_redo:
		undo_redo.create_action("Level Builder: fill selection")
		result = GENERATOR.fill_selection(root, bounds, archetype_id, seed_value, undo_redo)
		undo_redo.commit_action()
	else:
		result = GENERATOR.fill_selection(root, bounds, archetype_id, seed_value, null)
	_gen_status.text = String(result.get("message", "Nothing happened."))
	_refresh_units()


# ---------------------------------------------------------------------------
# Layers tab
# ---------------------------------------------------------------------------

func _build_layers_tab() -> void:
	var page := _tab_page("Layers")
	_section_label(page, "Apply a role to the selected nodes")

	_layer_profiles = LAYER_TOOLS.load_profiles()
	for profile in _layer_profiles:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		page.add_child(row)
		var name_label := Label.new()
		name_label.text = profile.profile_name
		name_label.tooltip_text = profile.summary
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP  # so the tooltip shows
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var apply := Button.new()
		apply.text = "Apply to selection"
		apply.tooltip_text = profile.summary
		apply.pressed.connect(_on_apply_layer_profile.bind(profile))
		row.add_child(apply)

	page.add_child(HSeparator.new())
	var names_button := Button.new()
	names_button.text = "Name project layers 1–6"
	names_button.tooltip_text = "Writes World/Player/Enemy/Projectile/Pickup/Trigger into Project Settings. Global and not undoable — asks first."
	names_button.pressed.connect(_on_name_layers)
	page.add_child(names_button)

	var audit_button := Button.new()
	audit_button.text = "Audit Layers in Open Scene"
	audit_button.pressed.connect(_on_audit_layers)
	page.add_child(audit_button)

	_layer_status = Label.new()
	_layer_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_layer_status.add_theme_color_override("font_color", DIM)
	page.add_child(_layer_status)


func _selection() -> Array:
	if not Engine.is_editor_hint():
		return []
	return EditorInterface.get_selection().get_selected_nodes()


func _on_apply_layer_profile(profile: Resource) -> void:
	var nodes := _selection()
	if nodes.is_empty():
		_layer_status.text = "Select some nodes in the scene tree first."
		return
	var changed := 0
	if undo_redo:
		undo_redo.create_action("Level Builder: apply %s layers" % profile.profile_name)
		changed = LAYER_TOOLS.apply_profile(nodes, profile, undo_redo)
		undo_redo.commit_action()
	else:
		changed = LAYER_TOOLS.apply_profile(nodes, profile, null)
	_layer_status.text = "%s: %d body(ies) updated." % [profile.profile_name, changed] if changed > 0 \
		else "%s: nothing to change in the selection." % profile.profile_name


func _on_name_layers() -> void:
	# built once and kept: a dialog per press piles up ownerless children on the
	# dock for as long as the editor is open
	if _names_confirm == null:
		_names_confirm = ConfirmationDialog.new()
		_names_confirm.dialog_text = "Write layer names 1–6 (World, Player, Enemy, Projectile, Pickup, Trigger) into Project Settings?\n\nThis is project-global and not undoable."
		_names_confirm.confirmed.connect(func() -> void:
			LAYER_TOOLS.apply_layer_names(LAYER_TOOLS.DEFAULT_LAYER_NAMES, true)
			_layer_status.text = "Layer names written to Project Settings."
		)
		add_child(_names_confirm)
	_names_confirm.popup_centered()


func _on_audit_layers() -> void:
	var root := _edited_root()
	if root == null:
		_layer_status.text = "Open a scene first."
		return
	var findings: Array[Dictionary] = LAYER_TOOLS.audit(root)
	if findings.is_empty():
		_layer_status.text = "Layers look sane."
		return
	var lines := PackedStringArray()
	for finding in findings:
		lines.append(String(finding["message"]))
	_layer_status.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# Colliders tab
# ---------------------------------------------------------------------------

func _build_colliders_tab() -> void:
	var page := _tab_page("Colliders")
	_section_label(page, "Generate collision for selected meshes")

	_policy_option = OptionButton.new()
	for policy_name in COLLIDER_TOOLS.POLICY_NAMES:
		_policy_option.add_item(policy_name)
	page.add_child(_policy_option)

	_collider_role_option = OptionButton.new()
	_collider_role_option.add_item("Layer role: World")
	for i in range(1, _layer_profiles.size()):
		_collider_role_option.add_item("Layer role: " + _layer_profiles[i].profile_name)
	page.add_child(_collider_role_option)

	_skip_existing_check = CheckBox.new()
	_skip_existing_check.text = "Skip meshes that already collide"
	_skip_existing_check.button_pressed = true
	page.add_child(_skip_existing_check)

	var generate_button := Button.new()
	generate_button.text = "Generate for Selection"
	generate_button.pressed.connect(_on_generate_colliders)
	page.add_child(generate_button)

	_collider_status = Label.new()
	_collider_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_collider_status.add_theme_color_override("font_color", DIM)
	page.add_child(_collider_status)

	var hint := Label.new()
	hint.text = "Trimesh for static world, convex for props, fitted for cheap approximations. The layer role lands on bodies this tool creates."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", DIM)
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(hint)


func _on_generate_colliders() -> void:
	var root := _edited_root()
	var nodes := _selection()
	if root == null or nodes.is_empty():
		_collider_status.text = "Select meshes (or their parents) in the scene tree first."
		return
	var profile: Resource = _layer_profiles[_collider_role_option.selected] if _collider_role_option.selected < _layer_profiles.size() else null
	var made := 0
	if undo_redo:
		undo_redo.create_action("Level Builder: generate colliders")
		made = COLLIDER_TOOLS.generate(nodes, _policy_option.selected, root, profile, undo_redo,
			_skip_existing_check.button_pressed)
		undo_redo.commit_action()
	else:
		made = COLLIDER_TOOLS.generate(nodes, _policy_option.selected, root, profile, null,
			_skip_existing_check.button_pressed)
	_collider_status.text = "%d collider(s) created." % made if made > 0 \
		else "Nothing to do — no shapeless meshes in the selection."


# ---------------------------------------------------------------------------
# Assets tab
# ---------------------------------------------------------------------------

func _build_assets_tab() -> void:
	var page := _tab_page("Assets")

	var folder_row := HBoxContainer.new()
	folder_row.add_theme_constant_override("separation", 6)
	page.add_child(folder_row)
	var add_folder := Button.new()
	add_folder.text = "Add folder…"
	add_folder.pressed.connect(_on_add_folder)
	folder_row.add_child(add_folder)
	var remove_folder := Button.new()
	remove_folder.text = "Remove"
	remove_folder.pressed.connect(_on_remove_folder)
	folder_row.add_child(remove_folder)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.pressed.connect(_refresh_assets)
	folder_row.add_child(rescan)

	_folder_list = ItemList.new()
	_folder_list.custom_minimum_size = Vector2(0, 52)
	page.add_child(_folder_list)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	page.add_child(filter_row)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search assets…"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(func(_t: String) -> void: _refill_asset_list())
	filter_row.add_child(_search_edit)
	_category_option = OptionButton.new()
	_category_option.item_selected.connect(func(_i: int) -> void: _refill_asset_list())
	filter_row.add_child(_category_option)

	_asset_list = PaletteList.new()
	_asset_list.name = "AssetList"
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_list.custom_minimum_size = Vector2(0, 150)  # a short dock scrolls the page, it doesn't squash the palette flat
	_asset_list.max_columns = 0
	_asset_list.icon_mode = ItemList.ICON_MODE_TOP
	_asset_list.fixed_icon_size = Vector2i(48, 48)
	_asset_list.same_column_width = true
	_asset_list.item_selected.connect(_on_asset_selected)
	page.add_child(_asset_list)

	_place_status = Label.new()
	_place_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_status.add_theme_color_override("font_color", DIM)
	_place_status.text = "Click an asset to start placing. Drag also works, without the smart defaults."
	page.add_child(_place_status)


func _scan_dirs() -> PackedStringArray:
	var stored: Variant = PREFS.get_pref("palette_dirs", null)
	if stored is Array and (stored as Array).size() > 0:
		var dirs := PackedStringArray()
		for d in stored:
			dirs.append(String(d))
		return dirs
	# first open: the greybox set, if this project has it. Scanning the greybox
	# folder itself keeps demo_level/demo_walk scenes out of the palette.
	if DirAccess.dir_exists_absolute("res://addons/level_builder/greybox"):
		return PackedStringArray(["res://addons/level_builder/greybox"])
	return PackedStringArray()


func _on_add_folder() -> void:
	if _folder_dialog == null:
		_folder_dialog = EditorFileDialog.new()
		_folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		_folder_dialog.dir_selected.connect(_on_folder_picked)
		add_child(_folder_dialog)
	_folder_dialog.popup_centered_ratio(0.5)


func _on_folder_picked(dir: String) -> void:
	var dirs := _scan_dirs()
	if dir not in dirs:
		dirs.append(dir)
		PREFS.set_pref("palette_dirs", Array(dirs))
	_refresh_assets()


func _on_remove_folder() -> void:
	var selected := _folder_list.get_selected_items()
	if selected.is_empty():
		return
	var dirs := _scan_dirs()
	dirs.remove_at(selected[0])
	PREFS.set_pref("palette_dirs", Array(dirs))
	_refresh_assets()


func _refresh_assets() -> void:
	var dirs := _scan_dirs()
	# a rescan keeps the category you were looking at, while it's still there
	var keep: String = _category_option.get_item_text(_category_option.selected) if _category_option.selected > 0 else ""
	_folder_list.clear()
	for dir in dirs:
		_folder_list.add_item(dir)
	_entries = PALETTE.scan(dirs)
	_category_option.clear()
	_category_option.add_item("All")
	for category in PALETTE.categories(_entries):
		_category_option.add_item(category)
		if category == keep:
			_category_option.select(_category_option.item_count - 1)
	_refill_asset_list()


# A model dropped into a palette folder this session shows up when the Assets tab
# opens or the files change, no Rescan needed. Folders that didn't change are left
# alone, so the thumbnails and the picked asset stay put.
func _refresh_assets_if_changed() -> void:
	var fresh: Array[Dictionary] = PALETTE.scan(_scan_dirs())
	if fresh.size() == _entries.size():
		var same := true
		for i in fresh.size():
			if String(fresh[i]["path"]) != String(_entries[i]["path"]):
				same = false
				break
		if same:
			return
	_refresh_assets()


func _refill_asset_list() -> void:
	_asset_list.clear()
	var category := ""
	if _category_option.selected > 0:
		category = _category_option.get_item_text(_category_option.selected)
	var visible_entries: Array[Dictionary] = PALETTE.filter(_entries, _search_edit.text, category)
	for entry in visible_entries:
		var idx := _asset_list.add_item(String(entry["name"]))
		_asset_list.set_item_metadata(idx, entry)
		_asset_list.set_item_tooltip(idx, String(entry["path"]))
		if Engine.is_editor_hint():
			EditorInterface.get_resource_previewer().queue_resource_preview(
				String(entry["path"]), self, "_on_thumb_ready", idx)


func _on_thumb_ready(path: String, preview: Texture2D, _small: Texture2D, userdata: Variant) -> void:
	var idx := int(userdata)
	if preview == null or idx >= _asset_list.item_count:
		return
	var meta: Dictionary = _asset_list.get_item_metadata(idx)
	if String(meta["path"]) == path:
		_asset_list.set_item_icon(idx, preview)


func _on_asset_selected(idx: int) -> void:
	if placement == null:
		return
	var meta: Dictionary = _asset_list.get_item_metadata(idx)
	placement.arm(String(meta["path"]), String(meta["category"]))
	_place_status.text = "Placing: %s — move over the viewport, click to drop. R rotates, Esc or right-click stops." % String(meta["name"])


func stop_placing() -> void:
	if placement:
		placement.disarm()
	if _asset_list:
		_asset_list.deselect_all()
	if _place_status:
		_place_status.text = "Click an asset to start placing. Drag also works, without the smart defaults."


# ---------------------------------------------------------------------------
# Footer: Check Level + Test Walk
# ---------------------------------------------------------------------------

func _on_check_level() -> void:
	var root := _edited_root()
	if _check_dialog == null:
		_check_dialog = AcceptDialog.new()
		_check_dialog.title = "Check Level"
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(460, 260)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_check_dialog.add_child(scroll)
		_check_rows = VBoxContainer.new()
		_check_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(_check_rows)
		add_child(_check_dialog)
	if root == null:
		_render_findings(_check_rows, [], "Open a scene first.")
	else:
		var findings: Array[Dictionary] = LEVEL_CHECK.check(root)
		_render_findings(_check_rows, findings, "Walkable. Green across the board — go press Test Walk.")
	_check_dialog.popup_centered()


func _on_test_walk() -> void:
	var root := _edited_root()
	if root == null:
		_on_check_level()  # explains "open a scene first"
		return
	if root.scene_file_path == "":
		if _save_first == null:
			_save_first = AcceptDialog.new()
			_save_first.dialog_text = "Save your scene once (Ctrl+S) so Test Walk has a file to run."
			add_child(_save_first)
		_save_first.popup_centered()
		return
	if _walk_confirm == null:
		_walk_confirm = ConfirmationDialog.new()
		_walk_confirm.title = "Test Walk"
		_walk_confirm.confirmed.connect(_launch_walk)
		add_child(_walk_confirm)
	var text := "Saves the scene, then runs it with the bundled walker at PlayerSpawn."
	var custom := String(PREFS.get_pref("test_player_scene", ""))
	if custom != "" and ResourceLoader.exists(custom):
		text += "\n\nUsing your custom player: " + custom
	elif LAUNCHER.controller_pack_present():
		text += "\n\nController pack detected — point 'test_player_scene' in user://level_builder_prefs.json at your player scene to walk with it instead."
	_walk_confirm.dialog_text = text
	_walk_confirm.popup_centered()


func _launch_walk() -> void:
	var root := _edited_root()
	if root == null:
		return
	EditorInterface.save_scene()
	var level: PackedScene = load(root.scene_file_path)
	if level == null:
		push_error("Level Builder: couldn't reload " + root.scene_file_path)
		return
	var custom_player: PackedScene = null
	var custom := String(PREFS.get_pref("test_player_scene", ""))
	if custom != "" and ResourceLoader.exists(custom):
		custom_player = load(custom)
	if not LAUNCHER.save_and_play(level, custom_player):
		push_error("Level Builder: Test Walk failed to build its wrapper scene.")
