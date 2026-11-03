class_name Lex01Content
extends RefCounted

## Loads every LEX-01 input the game needs: the vocabulary file, **every** scenario
## file in res://data/scenarios/ and the room layout.
##
## This is the only place that knows where content lives. Nothing in the gameplay code
## knows a single German word, prop path or position, which is what makes a new learning
## situation a data change instead of a code change.
##
## Bad content is reported through `errors` and never crashes the game: an unknown lemma
## id or an undeclared placement slot names the record instead of taking the room down.

const VOCABULARY_PATH: String = "res://data/vocabulary/de_a1_starter.json"
const SCENARIO_DIR: String = "res://data/scenarios"
const ROOM_PATH: String = "res://data/room/lex01_room.json"

const ALLOWED_ACTION_TYPES: PackedStringArray = ["find_select", "bring_deliver", "respond"]
# scene_state keys that are not lemma ids.
const SCENE_STATE_SPECIAL_KEYS: PackedStringArray = ["focus_object", "compared_object", "size_evidence"]

var lemmas: Dictionary = {}
var scenarios: Array[Dictionary] = []
var scenario_files: PackedStringArray = []
var room: Dictionary = {}
var errors: PackedStringArray = []


func load_all() -> bool:
	var vocabulary: Variant = _read_json(VOCABULARY_PATH)
	if not (vocabulary is Dictionary):
		errors.append("cannot read vocabulary file " + VOCABULARY_PATH)
		return false
	for lemma: Variant in vocabulary.get("lemmas", []):
		if lemma is Dictionary and lemma.has("id"):
			lemmas[String(lemma["id"])] = lemma
	if lemmas.is_empty():
		errors.append("vocabulary file has no lemmas")
		return false

	var layout: Variant = _read_json(ROOM_PATH)
	if not (layout is Dictionary):
		errors.append("cannot read room layout " + ROOM_PATH)
		return false
	room = layout
	_validate_room_shell()

	var directory: DirAccess = DirAccess.open(SCENARIO_DIR)
	if directory == null:
		errors.append("cannot open scenario directory " + SCENARIO_DIR)
		return false
	var file_names: Array[String] = []
	for file_name: String in directory.get_files():
		# DirAccess also reports the *.import sidecars Godot generates.
		if file_name.ends_with(".json"):
			file_names.append(file_name)
	file_names.sort()
	if file_names.is_empty():
		errors.append("no scenario files in " + SCENARIO_DIR)
		return false

	for file_name: String in file_names:
		var path: String = SCENARIO_DIR + "/" + file_name
		var document: Variant = _read_json(path)
		if not (document is Dictionary):
			errors.append("cannot read scenario file " + path)
			continue
		scenario_files.append(path)
		for scenario: Variant in document.get("scenarios", []):
			if not (scenario is Dictionary):
				errors.append("scenario record is not an object in " + path)
				continue
			scenario["_source_file"] = path
			_validate_scenario(scenario, path)
			scenarios.append(scenario)

	if scenarios.is_empty():
		errors.append("no scenario records loaded")
		return false
	_validate_scenario_rooms()
	return errors.is_empty()


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed


func _validate_scenario(scenario: Dictionary, path: String) -> void:
	var id: String = String(scenario.get("id", "<no id>"))
	var action: String = String(scenario.get("action_type", ""))
	if not ALLOWED_ACTION_TYPES.has(action):
		errors.append("%s: unknown action_type '%s' (allowed: %s)" % [id, action, ", ".join(ALLOWED_ACTION_TYPES)])
	if String(scenario.get("utterance_de", "")).strip_edges().is_empty():
		errors.append("%s: empty utterance_de" % id)
	if String(scenario.get("feedback_correct_de", "")).strip_edges().is_empty():
		errors.append("%s: missing feedback_correct_de" % id)
	if String(scenario.get("feedback_wrong_de", "")).strip_edges().is_empty():
		errors.append("%s: missing feedback_wrong_de" % id)

	for lemma_id: String in _string_array(scenario.get("target_lemma_ids", [])):
		if not lemmas.has(lemma_id):
			errors.append("%s: unknown target lemma '%s'" % [id, lemma_id])
	for lemma_id: String in _string_array(scenario.get("feedback_lemma_ids", [])):
		if not lemmas.has(lemma_id):
			errors.append("%s: unknown feedback lemma '%s'" % [id, lemma_id])
	var verb: String = String(scenario.get("verb_lemma_id", ""))
	if not verb.is_empty() and not lemmas.has(verb):
		errors.append("%s: unknown verb lemma '%s'" % [id, verb])

	var option_ids: Array[String] = []
	for option: Variant in scenario.get("options", []):
		if not (option is Dictionary):
			errors.append("%s: option is not an object" % id)
			continue
		var option_id: String = String(option.get("id", ""))
		if option_id.is_empty() or option_ids.has(option_id):
			errors.append("%s: empty or duplicate option id '%s'" % [id, option_id])
			continue
		option_ids.append(option_id)
		if String(option.get("label_de", "")).strip_edges().is_empty():
			errors.append("%s: option %s has no label_de" % [id, option_id])
		for lemma_id: String in _string_array(option.get("lemma_ids", [])):
			if not lemmas.has(lemma_id):
				errors.append("%s: option %s references unknown lemma '%s'" % [id, option_id, lemma_id])
		if action != "respond":
			var scene_object: String = String(option.get("scene_object", ""))
			if scene_object.is_empty():
				errors.append("%s: option %s has no scene_object but action %s needs one" % [id, option_id, action])
			elif not ResourceLoader.exists(scene_object):
				errors.append("%s: option %s references a missing model %s" % [id, option_id, scene_object])
	if option_ids.size() < 2:
		errors.append("%s: fewer than two options" % id)
	if not option_ids.has(String(scenario.get("correct_option_id", ""))):
		errors.append("%s: correct_option_id is not one of the options" % id)

	var target: Variant = scenario.get("delivery_target", null)
	if target is Dictionary:
		var kind: String = String(target.get("kind", ""))
		if kind == "npc" and npc_config(String(target.get("npc", ""))).is_empty():
			errors.append("%s: delivery_target names an unknown npc '%s'" % [id, String(target.get("npc", ""))])
		if kind == "object":
			var target_path: String = String(target.get("scene_object", ""))
			if target_path.is_empty() or not ResourceLoader.exists(target_path):
				errors.append("%s: delivery_target model is missing: %s" % [id, target_path])

	var state: Variant = scenario.get("scene_state", null)
	if state is Dictionary:
		for key: String in state:
			if SCENE_STATE_SPECIAL_KEYS.has(key):
				continue
			if not lemmas.has(key):
				errors.append("%s: scene_state key '%s' is not a known lemma id" % [id, key])
				continue
			var object_path: String = object_path(key)
			if object_path.is_empty():
				errors.append("%s: scene_state lemma '%s' has no scene_object" % [id, key])
			elif not ResourceLoader.exists(object_path):
				errors.append("%s: scene_state model is missing: %s" % [id, object_path])
			var slot: Dictionary = placement_slot(String(state[key]))
			if slot.is_empty():
				errors.append("%s: scene_state slot '%s' is not declared in %s" % [id, String(state[key]), ROOM_PATH])


func _validate_room_shell() -> void:
	for required: String in ["npcs", "cameras", "candidate_slots", "anchors", "placement_slots", "hold", "delivery"]:
		if not (room.get(required, null) is Dictionary):
			errors.append("room layout is missing the '%s' section" % required)
	for slot_name: String in placement_slots():
		var slot: Dictionary = placement_slot(slot_name)
		var anchor: String = String(slot.get("anchor", ""))
		if anchor.is_empty() or not ResourceLoader.exists(anchor):
			errors.append("placement slot '%s' has no usable anchor model: %s" % [slot_name, anchor])
		if anchor_entries(anchor).is_empty():
			errors.append("placement slot '%s' anchor has no position data: %s" % [slot_name, anchor])
		if not ["on_top", "at_front"].has(String(slot.get("mode", ""))):
			errors.append("placement slot '%s' uses an unknown mode '%s'" % [slot_name, String(slot.get("mode", ""))])
func _validate_scenario_rooms() -> void:
	for scenario: Dictionary in scenarios:
		var slots: Array = candidate_slots(String(scenario.get("context", "")))
		if slots.size() < 2:
			errors.append("%s: context '%s' has fewer than two candidate positions" % [String(scenario.get("id", "?")), String(scenario.get("context", ""))])


# region lookups

func lemma(lemma_id: String) -> Dictionary:
	return lemmas.get(lemma_id, {}) as Dictionary


func object_path(lemma_id: String) -> String:
	var record: Dictionary = lemma(lemma_id)
	if record.is_empty():
		return ""
	# Verb and adjective lemmas carry a JSON null here, and String(null) is not a conversion.
	var value: Variant = record.get("scene_object", null)
	return "" if value == null else String(value)


func scenario(id: String) -> Dictionary:
	for candidate: Dictionary in scenarios:
		if String(candidate.get("id", "")) == id:
			return candidate
	return {}


func days() -> Array[int]:
	var result: Array[int] = []
	for scenario: Dictionary in scenarios:
		var day: int = int(scenario.get("day", 1))
		if not result.has(day):
			result.append(day)
	result.sort()
	return result


func scenarios_for_day(day: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for scenario: Dictionary in scenarios:
		if int(scenario.get("day", 1)) == day:
			result.append(scenario)
	return result


func npc_config(npc_name: String) -> Dictionary:
	var section: Variant = room.get("npcs", null)
	if section is Dictionary and section.has(npc_name):
		return section[npc_name] as Dictionary
	return {}


func camera_for(context: String) -> Dictionary:
	var section: Variant = room.get("cameras", null)
	if section is Dictionary and section.has(context):
		return section[context] as Dictionary
	if section is Dictionary and section.has("default"):
		return section["default"] as Dictionary
	return {}


func candidate_slots(context: String) -> Array:
	var section: Variant = room.get("candidate_slots", null)
	if section is Dictionary and section.has(context):
		return section[context] as Array
	if section is Dictionary and section.has("default"):
		return section["default"] as Array
	return []


func placement_slots() -> Array[String]:
	var section: Variant = room.get("placement_slots", null)
	var result: Array[String] = []
	if section is Dictionary:
		for key: String in section:
			result.append(key)
	result.sort()
	return result


func placement_slot(slot_name: String) -> Dictionary:
	var section: Variant = room.get("placement_slots", null)
	if section is Dictionary and section.has(slot_name):
		return section[slot_name] as Dictionary
	return {}


func anchor_entries(scene_object: String) -> Dictionary:
	var section: Variant = room.get("anchors", null)
	if section is Dictionary and section.has(scene_object):
		return section[scene_object] as Dictionary
	return {}


func anchor_position(scene_object: String, context: String) -> Vector3:
	var entries: Dictionary = anchor_entries(scene_object)
	for key: String in [context, "default"]:
		if entries.has(key):
			return _vector3(entries[key])
	return Vector3.ZERO


func hold_config() -> Dictionary:
	var section: Variant = room.get("hold", null)
	return section as Dictionary if section is Dictionary else {}


func delivery_config() -> Dictionary:
	var section: Variant = room.get("delivery", null)
	return section as Dictionary if section is Dictionary else {}


func highlight_color(kind: String, fallback: Color) -> Color:
	var section: Variant = room.get("highlight_colors", null)
	if section is Dictionary and section.has(kind):
		var raw: Variant = section[kind]
		if raw is Array and (raw as Array).size() >= 4:
			return Color(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	return fallback


# endregion

func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			result.append(String(entry))
	return result


func _vector3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
