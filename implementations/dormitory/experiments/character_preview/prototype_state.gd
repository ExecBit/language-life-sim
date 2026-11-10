extends RefCounted

const VERSION := 1
var phase := "offer"
var cup_location := "lena"
var identified := false
var completed: Array[String] = []
var units: Array[String] = []

func commit(event_id: String, action: String) -> bool:
	if event_id in completed:
		return false
	match action:
		"accept":
			if phase != "offer" or cup_location != "lena": return false
			cup_location = "player"
			phase = "accepted"
		"decline":
			if phase != "offer" or cup_location != "lena": return false
			cup_location = "table"
			phase = "declined"
		"take":
			if phase == "offer" or cup_location != "table": return false
			cup_location = "player"
		"give":
			if phase == "offer" or cup_location != "player": return false
			cup_location = "lena"
			phase = "returned"
		"place":
			if phase == "offer" or cup_location != "player": return false
			cup_location = "table"
		"identify":
			if phase == "offer" or identified: return false
			identified = true
		_:
			return false
	completed.append(event_id)
	var unit := {"accept": "ja", "decline": "nein", "identify": "was_ist_das", "give": "gib"}.get(action, "") as String
	if not unit.is_empty() and unit not in units: units.append(unit)
	return true

func snapshot() -> Dictionary:
	return {"version": VERSION, "phase": phase, "cup_location": cup_location,
		"identified": identified, "completed": completed.duplicate(), "units": units.duplicate()}

func restore(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.get("version") != VERSION: return false
	if data.get("phase") not in ["offer", "accepted", "declined", "returned"]: return false
	if data.get("cup_location") not in ["lena", "player", "table"]: return false
	if not data.get("identified") is bool: return false
	for key in ["completed", "units"]:
		if not data.get(key) is Array: return false
		for entry in data[key]:
			if not entry is String: return false
	if data.phase == "offer" and (data.cup_location != "lena" or data.identified): return false
	phase = data.phase
	cup_location = data.cup_location
	identified = data.identified
	completed.assign(data.completed)
	units.assign(data.units)
	return true
