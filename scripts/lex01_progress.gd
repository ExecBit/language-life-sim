class_name Lex01Progress
extends RefCounted

## What the player has actually done with each lemma, and nothing beyond that.
##
## Counting rules, stated because they decide what the end-of-day summary may claim:
##  * `encountered` - the lemma was a target of a presented scenario (once per presentation).
##  * `correct` / `incorrect` - one attempt attributed to the scenario's `target_lemma_ids`.
##    A lemma that only appeared as an answer alternative is never credited or blamed.
##  * `option_shown` - the lemma appeared as an answer alternative in a presented scenario.
##  * `revisited` - the lemma was targeted by a scenario that declares `revisit_of`.
##  * `skipped` - the player left the scenario without a correct answer.
## There is deliberately no mastery score, no confidence value and no spaced-repetition
## scheduling here: nothing in this slice measures retention, so nothing may report it.

const SAVE_PATH: String = "user://lex01_progress.json"
const SAVE_VERSION: int = 1
const STAT_KEYS: PackedStringArray = ["encountered", "correct", "incorrect", "revisited", "skipped", "option_shown"]

var lemma_stats: Dictionary = {}
var scenario_log: Dictionary = {}
var current_day: int = 1
var days_finished: Array[int] = []


func reset() -> void:
	lemma_stats = {}
	scenario_log = {}
	current_day = 1
	days_finished = []


func present(scenario: Dictionary) -> void:
	var targets: Array[String] = _string_array(scenario.get("target_lemma_ids", []))
	var is_revisit: bool = not String(scenario.get("revisit_of", "")).is_empty()
	for lemma_id: String in targets:
		var stats: Dictionary = _stats_for(lemma_id)
		stats["encountered"] = int(stats["encountered"]) + 1
		if is_revisit:
			stats["revisited"] = int(stats["revisited"]) + 1
	for lemma_id: String in _answer_lemmas(scenario):
		if targets.has(lemma_id):
			continue
		var stats: Dictionary = _stats_for(lemma_id)
		stats["option_shown"] = int(stats["option_shown"]) + 1
	var log: Dictionary = _log_for(scenario)
	log["day"] = int(scenario.get("day", 1))
	log["presented"] = true
	log["revisit_of"] = String(scenario.get("revisit_of", ""))


func attempt(scenario: Dictionary, was_correct: bool) -> void:
	for lemma_id: String in _string_array(scenario.get("target_lemma_ids", [])):
		var stats: Dictionary = _stats_for(lemma_id)
		if was_correct:
			stats["correct"] = int(stats["correct"]) + 1
		else:
			stats["incorrect"] = int(stats["incorrect"]) + 1
	var log: Dictionary = _log_for(scenario)
	var attempts: int = int(log.get("attempts", 0)) + 1
	log["attempts"] = attempts
	if was_correct and not bool(log.get("solved", false)):
		log["solved"] = true
		log["first_correct_attempt"] = attempts


func skip(scenario: Dictionary) -> void:
	for lemma_id: String in _string_array(scenario.get("target_lemma_ids", [])):
		var stats: Dictionary = _stats_for(lemma_id)
		stats["skipped"] = int(stats["skipped"]) + 1
	var log: Dictionary = _log_for(scenario)
	log["skipped"] = true


func set_current_day(day: int) -> void:
	current_day = day


func mark_day_finished(day: int) -> void:
	if not days_finished.has(day):
		days_finished.append(day)
		days_finished.sort()


func stats(lemma_id: String) -> Dictionary:
	return lemma_stats.get(lemma_id, _empty_stats()) as Dictionary


func scenario_entry(scenario_id: String) -> Dictionary:
	return scenario_log.get(scenario_id, {}) as Dictionary


func has_progress() -> bool:
	return not lemma_stats.is_empty()


## Lemma ids the player met as a target, most-met first.
func touched_lemma_ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in lemma_stats:
		if int((lemma_stats[key] as Dictionary)["encountered"]) > 0:
			result.append(String(key))
	# Insertion sort: more encounters first, then the lemma id. No comparator callbacks.
	for index: int in range(1, result.size()):
		var moving: String = result[index]
		var scan: int = index - 1
		while scan >= 0 and _sorts_after(result[scan], moving):
			result[scan + 1] = result[scan]
			scan -= 1
		result[scan + 1] = moving
	return result


func _sorts_after(a: String, b: String) -> bool:
	var left: Dictionary = stats(a)
	var right: Dictionary = stats(b)
	if int(left["encountered"]) != int(right["encountered"]):
		return int(left["encountered"]) < int(right["encountered"])
	return a > b


## The end-of-day summary lines. This is the only place the English gloss from the
## vocabulary file is ever shown, so German stays the only language during play.
func summary_lines(content: Lex01Content) -> Array[String]:
	var lines: Array[String] = []
	for lemma_id: String in touched_lemma_ids():
		var record: Dictionary = content.lemma(lemma_id)
		if record.is_empty():
			continue
		var name: String = String(record.get("lemma", lemma_id))
		var article_value: Variant = record.get("article", null)
		var article: String = "" if article_value == null else String(article_value)
		var display: String = (article + " " + name).strip_edges()
		var gloss: String = String(record.get("en", ""))
		var values: Dictionary = stats(lemma_id)
		lines.append("%s (%s) - begegnet %d, richtig %d, falsch %d, wiederholt %d, übersprungen %d" % [
			display, gloss,
			int(values["encountered"]), int(values["correct"]), int(values["incorrect"]),
			int(values["revisited"]), int(values["skipped"]),
		])
	return lines


func save_run() -> bool:
	var document: Dictionary = {
		"version": SAVE_VERSION,
		"current_day": current_day,
		"days_finished": days_finished,
		"lemma_stats": lemma_stats,
		"scenario_log": scenario_log,
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "  "))
	file.flush()
	return true


func load_run() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary) or int(parsed.get("version", 0)) != SAVE_VERSION:
		return false
	lemma_stats = {}
	var stored_stats: Variant = parsed.get("lemma_stats", {})
	if stored_stats is Dictionary:
		for key: Variant in stored_stats:
			var raw: Variant = stored_stats[key]
			if raw is Dictionary:
				var entry: Dictionary = _empty_stats()
				for stat_key: String in STAT_KEYS:
					entry[stat_key] = int((raw as Dictionary).get(stat_key, 0))
				lemma_stats[String(key)] = entry
	scenario_log = {}
	var stored_log: Variant = parsed.get("scenario_log", {})
	if stored_log is Dictionary:
		for key: Variant in stored_log:
			if stored_log[key] is Dictionary:
				scenario_log[String(key)] = stored_log[key]
	current_day = int(parsed.get("current_day", 1))
	days_finished = []
	var stored_days: Variant = parsed.get("days_finished", [])
	if stored_days is Array:
		for day: Variant in stored_days:
			days_finished.append(int(day))
	return true


func delete_run() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	reset()


func totals() -> Dictionary:
	var result: Dictionary = {"encountered": 0, "correct": 0, "incorrect": 0, "revisited": 0, "skipped": 0}
	for key: Variant in lemma_stats:
		var values: Dictionary = lemma_stats[key] as Dictionary
		for stat_key: String in result:
			result[stat_key] = int(result[stat_key]) + int(values.get(stat_key, 0))
	return result


## Scenario-level counters for the status line: one solved scenario counts one correct attempt,
## everything else the player tried counts as a wrong answer.
func scenario_totals() -> Dictionary:
	var solved: int = 0
	var skipped: int = 0
	var attempts: int = 0
	for key: Variant in scenario_log:
		var entry: Dictionary = scenario_log[key] as Dictionary
		attempts += int(entry.get("attempts", 0))
		if bool(entry.get("solved", false)):
			solved += 1
		if bool(entry.get("skipped", false)):
			skipped += 1
	return {"solved": solved, "skipped": skipped, "attempts": attempts, "wrong_attempts": maxi(attempts - solved, 0)}


func _stats_for(lemma_id: String) -> Dictionary:
	if not lemma_stats.has(lemma_id):
		lemma_stats[lemma_id] = _empty_stats()
	return lemma_stats[lemma_id] as Dictionary


func _log_for(scenario: Dictionary) -> Dictionary:
	var id: String = String(scenario.get("id", "<no id>"))
	if not scenario_log.has(id):
		scenario_log[id] = {"attempts": 0, "solved": false, "skipped": false, "first_correct_attempt": 0}
	return scenario_log[id] as Dictionary


func _empty_stats() -> Dictionary:
	var entry: Dictionary = {}
	for stat_key: String in STAT_KEYS:
		entry[stat_key] = 0
	return entry


func _answer_lemmas(scenario: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for option: Variant in scenario.get("options", []):
		if option is Dictionary:
			for lemma_id: String in _string_array((option as Dictionary).get("lemma_ids", [])):
				if not result.has(lemma_id):
					result.append(lemma_id)
	return result


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			result.append(String(entry))
	return result
