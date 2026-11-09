extends RefCounted
## One optional request per day/meal/item; no wall-clock deadline or dialogue timer.
const DURATION := 120.0 # active gameplay seconds for the first breakfast period
const STATUSES := ["available","offered","accepted","completed","declined","skipped"]

static func create(day: int, meal := "breakfast", item := "bread") -> Dictionary:
	return {"event_id":"%d:%s:%s" % [day,meal,item],"day":day,"meal":meal,"item":item,
		"status":"available","activity":"cooking","elapsed":0.0,"history":[],"reason":""}

static func mark(event: Dictionary, status: String) -> void:
	event.status = status
	if status not in event.history: event.history.append(status)
	event.activity = "waiting_for_item" if status == "accepted" else "cooking"

static func valid(event: Variant, day: int) -> bool:
	if not event is Dictionary: return false
	for key in ["event_id","meal","item","status","activity","reason"]:
		if not event.get(key) is String: return false
	if event.get("day") != day or event.event_id != "%d:%s:%s" % [day,event.meal,event.item]: return false
	if event.meal != "breakfast" or event.item != "bread": return false
	if event.status not in STATUSES or event.activity not in ["idle","cooking","waiting_for_item","finished"]: return false
	if not (event.get("elapsed") is int or event.get("elapsed") is float): return false
	if not is_finite(float(event.elapsed)) or event.elapsed < 0 or event.elapsed > DURATION: return false
	if not event.get("history") is Array: return false
	var seen := {}
	for status in event.history:
		if status not in STATUSES or seen.has(status): return false
		seen[status] = true
	return true
