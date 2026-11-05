@tool
extends EditorPlugin

# Level Builder — one dock, four tabs, two north-star buttons.
# No autoload and no rpg_core here: this pack doesn't speak the event bus,
# it builds scenes.
#
# The plugin also owns the viewport half of place mode: _handles everything so
# _forward_3d_gui_input keeps flowing, but we only ever eat events while the
# placement controller is armed — normal navigation stays untouched.

const DOCK_SCRIPT := preload("res://addons/level_builder/editor/level_builder_dock.gd")
const PLACEMENT_SCRIPT := preload("res://addons/level_builder/editor/placement_controller.gd")

var _dock: Control
var _placement  # placement_controller.gd instance, shared with the dock


func _enter_tree() -> void:
	_placement = PLACEMENT_SCRIPT.new()
	_dock = DOCK_SCRIPT.new()
	_dock.undo_redo = get_undo_redo()
	_dock.placement = _placement
	# Named here, not only in the dock's _ready: Godot 4.5 reads the tab title
	# the moment the dock is added, before _ready has run.
	_dock.name = "Level Builder"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _placement:
		_placement.disarm()
		_placement = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.free()
		_dock = null


func _handles(_object: Object) -> bool:
	return true


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _placement == null or not _placement.armed:
		return AFTER_GUI_INPUT_PASS
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		_placement.update_ghost(viewport_camera, (event as InputEventMouseMotion).position, root)
		return AFTER_GUI_INPUT_PASS  # never block navigation

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			var undo := get_undo_redo()
			undo.create_action("Level Builder: place asset")
			var placed: Node3D = _placement.commit(root, undo)
			undo.commit_action()
			if placed:
				return AFTER_GUI_INPUT_STOP
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			_stop_placing()
			return AFTER_GUI_INPUT_STOP

	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_ESCAPE:
			_stop_placing()
			return AFTER_GUI_INPUT_STOP
		if key.physical_keycode == KEY_R:
			_placement.rotate_step(-1 if key.shift_pressed else 1)
			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS


func _stop_placing() -> void:
	# route through the dock so its status label and selection reset too
	if _dock and _dock.has_method("stop_placing"):
		_dock.stop_placing()
	elif _placement:
		_placement.disarm()
