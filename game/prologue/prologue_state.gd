extends RefCounted

const VERSION := 5
const LOCATIONS := ["lena","anna","player","player_pocket","drawer_slot","tray","entrance_bag","bag_stand","key_tray","bell_stand","surface_common","surface_room","surface_side","nightstand","bedside_spare","kitchen_shelf","breakfast_table"]
const Cooking = preload("res://game/prologue/cooking_routine.gd")
var cooking := {}
var index := 0
var day := 1
var period := "day"
var finished := false
var items := {
	"cup":"tray", "bag":"entrance_bag", "room_key":"lena", "bell":"bell_stand", "bread":"kitchen_shelf",
}
var flags := {}
var completed: Array[String] = []
var entered: Array[String] = []
var units: Array[String] = []
var help := {}
var chosen_target := ""

func enter(step: Dictionary) -> bool:
	ensure_cooking()
	if str(step.id) in entered: return false
	if not apply_many(step.get("ops",[])): return false
	entered.append(str(step.id))
	for unit in step.get("units", []):
		if str(unit) not in units: units.append(str(unit))
	return true

func apply_many(operations: Array) -> bool:
	var old_cooking := cooking.duplicate(true)
	var old_items := items.duplicate()
	var old_flags := flags.duplicate(true)
	var old_day := day
	var old_period := period
	var old_finished := finished
	for operation in operations:
		if apply(operation): continue
		cooking = old_cooking
		items = old_items
		flags = old_flags
		day = old_day
		period = old_period
		finished = old_finished
		return false
	return true

func apply(op: Array) -> bool:
	match op[0]:
		"move": return transfer(str(op[1]), str(op[2]), str(op[3]))
		"flag": flags[str(op[1])] = op[2]
		"period": period = str(op[1])
		"sleep":
			if not flags.get("slept", false):
				if not stow_hand(): return false
				day += 1
				period = "morning"
				flags.slept = true
				ensure_cooking()
		"stow_hand": return stow_hand()
		"finish": finished = true
		_: return false
	return true

func stow_hand() -> bool:
	var item := held("player")
	if item == "": return true
	var preferred: String = {"room_key":"nightstand","cup":"bedside_spare","bag":"bag_stand","bread":"surface_common"}.get(item,"surface_side")
	for place in [preferred,"bedside_spare","surface_room","key_tray","surface_common","surface_side","tray"]:
		if place not in items.values(): return transfer(item,"player",place)
	return false

func held(actor: String) -> String:
	for item in items:
		if items[item] == actor: return item
	return ""

func transfer(item: String, source: String, destination: String) -> bool:
	if not items.has(item) or items[item] != source or source == destination or destination not in LOCATIONS: return false
	if destination in ["player_pocket","drawer_slot"] and item != "room_key": return false
	if destination in ["lena", "anna", "player"] and held(destination) != "": return false
	for other in items:
		if other != item and destination not in ["lena", "anna", "player"] and items[other] == destination: return false
	items[item] = destination
	return true

func complete(step: Dictionary, choice := "", payload := "") -> bool:
	var id := str(step.id)
	if id in completed: return false
	if id == "f_arrival" and cooking.get("status","") != "offered": return false
	if id == "f_offer" and cooking.get("status","") != "offered": return false
	var answers: Array = step.get("answers", [])
	var selected := {}
	if not answers.is_empty():
		for answer in answers:
			if str(answer.id) == choice: selected = answer
		if selected.is_empty(): return false
		if selected.get("intent", "") == "subject":
			if payload not in ["room_key", "bag"]: return false
	if step.get("wait", "") == "target":
		if payload not in step.get("targets", []): return false
	var operations: Array = selected.get("ops",[]).duplicate(true)
	if step.get("wait", "") == "take":
		operations.append(["move",str(step.item),str(step.source),"player"])
	if step.get("wait", "") == "give":
		operations.append(["move",str(step.item),"player",str(step.actor)])
	if step.get("wait", "") == "place":
		operations.append(["move",str(step.item),"player",str(step.anchor)])
	if step.get("wait", "") == "stored" and items.get(str(step.item)) != step.anchor: return false
	if step.get("wait", "") == "owned" and items.get(str(step.item)) != "player": return false
	if step.get("wait", "") == "optional": operations.append(["sleep"])
	if step.get("wait", "") == "sleep_end":
		if day != 2: return false
		operations.append(["stow_hand"])
		operations.append_array([["period","evening"],["flag","day2_sleep",true],["finish"]])
	if step.get("wait","") == "npc_take": operations.append(["move","bread","kitchen_shelf","lena"])
	if step.get("wait","") == "npc_place":
		operations.append(["move","bread","lena","breakfast_table"])
		operations.append(["flag","breakfast_done",true])
		operations.append(["flag","breakfast_result","skipped" if cooking.get("status","") == "skipped" else str(step.result)])
	if not apply_many(operations): return false
	if id == "f_offer": Cooking.mark(cooking,"accepted" if choice == "yes" else "declined")
	if id == "f_give": Cooking.mark(cooking,"completed")
	if step.get("wait","") == "npc_place":
		if cooking.get("status","") == "accepted": Cooking.mark(cooking,"completed")
		cooking.activity = "finished"
	if id in ["f_take","f_give"]:
		var usage := "assisted" if int(help.get(id+":repeat",0))+int(help.get(id+":show",0))+int(help.get(id+":helper",0)) > 0 else "independent"
		flags["nimm_usage" if id == "f_take" else "gib_usage"] = usage
	if step.get("wait","") == "target" or selected.get("intent","") == "subject": chosen_target = payload
	completed.append(id)
	if not selected.is_empty(): flags[id + ":choice"] = choice
	if choice in ["yes","no"]:
		var unit := "ja" if choice == "yes" else "nein"
		if unit not in units: units.append(unit)
	var next: int = selected.get("next", step.get("next", index + 1))
	index = next
	return true

func ask_help(step_id: String, kind: String) -> void:
	var key := step_id + ":" + kind
	help[key] = int(help.get(key, 0)) + 1
	var unit := "noch_einmal" if kind == "repeat" else "ich_verstehe_nicht"
	if unit not in units: units.append(unit)

func snapshot() -> Dictionary:
	return {"version": VERSION, "index": index, "day": day, "period": period, "finished": finished,
		"cooking":cooking.duplicate(true), "items": items.duplicate(), "flags": flags.duplicate(true), "completed": completed.duplicate(),
		"entered": entered.duplicate(), "units": units.duplicate(), "help": help.duplicate(), "chosen_target": chosen_target}

func restore(data: Variant, step_count: int) -> bool:
	if not data is Dictionary: return false
	if data.get("version") == 2: data = _upgrade_v2(data)
	if data.get("version") == 3: data = _upgrade_v3(data)
	if data.get("version") == 4:
		data = data.duplicate(true)
		data.version = VERSION
	if data.get("version") != VERSION: return false
	if not data.get("index") is float and not data.get("index") is int: return false
	if int(data.index) < 0 or int(data.index) >= step_count: return false
	if int(data.index) != data.index: return false
	if data.get("period") not in ["day", "evening", "morning"]: return false
	if not (data.get("day") is int or data.get("day") is float) or int(data.day) not in [1,2]: return false
	if not data.get("finished") is bool or not data.get("chosen_target") is String: return false
	for field in ["items", "flags", "help"]:
		if not data.get(field) is Dictionary: return false
	for field in ["completed", "entered", "units"]:
		if not data.get(field) is Array: return false
		var seen := {}
		for value in data[field]:
			if not value is String: return false
			if seen.has(value): return false
			seen[value] = true
	for value in data.flags.values():
		if not value is bool and not value is String: return false
	for value in data.help.values():
		if not (value is int or value is float) or value < 0: return false
	if data.chosen_target not in ["","bell","flashlight","apple","room_key","bag"]: return false
	if int(data.day) == 2 and not Cooking.valid(data.get("cooking"),2): return false
	if int(data.day) == 1 and data.get("cooking") != {}: return false
	var locations := {}
	if data.items.size() != items.size(): return false
	for item in items:
		if not data.items.has(item) or not data.items[item] is String: return false
		var destination: String = data.items[item]
		if destination not in LOCATIONS: return false
		if destination in ["player_pocket","drawer_slot"] and item != "room_key": return false
		if locations.has(destination): return false
		locations[destination] = item
	if data.flags.has("water_handoff_source"):
		if data.items.cup not in ["lena","anna"] or data.flags.water_handoff_source not in LOCATIONS or data.flags.water_handoff_source in ["player","player_pocket","lena","anna","drawer_slot"]: return false
	cooking = data.cooking.duplicate(true)
	index = int(data.index)
	day = int(data.day)
	period = data.period
	finished = data.finished
	items = data.items.duplicate()
	flags = data.flags.duplicate(true)
	help = data.help.duplicate()
	completed.assign(data.completed)
	entered.assign(data.entered)
	units.assign(data.units)
	chosen_target = data.chosen_target
	return true

func _upgrade_v2(old: Dictionary) -> Dictionary:
	# The first eight steps are unchanged. Completed v2 saves resume at the new morning.
	var data := old.duplicate(true)
	if not data.get("items") is Dictionary or not data.get("completed") is Array or not data.get("entered") is Array: return {}
	if data.items.size() != 4 or data.items.has("bread"): return {}
	if not (data.get("index") is int or data.get("index") is float) or data.index < 0 or data.index > 9: return {}
	data.version = 3
	data.items.bread = "kitchen_shelf"
	if int(data.get("day",0)) == 2:
		data.index = 8
		data.finished = false
		data.completed.erase("e_morning")
		data.completed.erase("complete")
		data.entered.erase("e_morning")
		data.entered.erase("complete")
		for item in data.items:
			if data.items[item] == "player":
				data.items[item] = {"room_key":"nightstand","cup":"bedside_spare","bag":"bag_stand"}.get(item,"bedside_spare")
	return data

func ensure_cooking() -> void:
	if day == 2 and cooking.is_empty(): cooking = Cooking.create(day)

func offer_cooking() -> bool:
	ensure_cooking()
	if cooking.get("status","") != "available" or cooking.get("activity","") != "cooking": return false
	if items.bread != "kitchen_shelf" or held("lena") != "": return false
	Cooking.mark(cooking,"offered")
	return true

func skip_cooking(reason: String) -> bool:
	ensure_cooking()
	if cooking.get("status","") not in ["available","offered","accepted"]: return false
	Cooking.mark(cooking,"skipped")
	cooking.reason = reason
	return true

func finish_without_loaf() -> void:
	# A loaf held by the player stays there. No remote take or replacement copy.
	if cooking.get("status","") not in ["declined","skipped"]: skip_cooking("unavailable")
	cooking.activity = "finished"
	flags.breakfast_done = true
	flags.breakfast_result = str(cooking.status)

func _upgrade_v3(old: Dictionary) -> Dictionary:
	var data := old.duplicate(true)
	if not data.get("flags") is Dictionary or not (data.get("index") is float or data.get("index") is int): return {}
	data.version = VERSION
	data.cooking = {}
	if int(data.get("day",0)) != 2: return data
	var event := Cooking.create(2)
	var i := int(data.index)
	if i == 9: Cooking.mark(event,"offered")
	elif i in [10,11,12]:
		Cooking.mark(event,"offered")
		Cooking.mark(event,"accepted")
		if i == 12: Cooking.mark(event,"completed")
	elif i in [13,14]:
		Cooking.mark(event,"offered")
		Cooking.mark(event,"declined")
	elif i >= 15:
		Cooking.mark(event,"completed" if data.flags.get("breakfast_result","") == "helped" else "declined")
		event.activity = "finished"
	data.cooking = event
	return data
