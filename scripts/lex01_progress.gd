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
##  * `assisted` / `unaided` - a correct answer that was given with the Russian translation of
##    that task on screen counts as `assisted`, one given without it counts as `unaided`. The
##    guided first example shows its translation without being asked, so it can only ever be
##    assisted. Nothing here measures retention: an assisted answer is a real answer, it is just
##    not evidence that the German sentence was understood on its own.
## Onboarding is stored here too, because "has this player been shown the controls yet" is run
## state and there is no reason for a second save file.
## There is deliberately no mastery score, no confidence value and no spaced-repetition
## scheduling here: nothing in this slice measures retention, so nothing may report it.

const SAVE_PATH: String = "user://lex01_progress.json"
const SAVE_VERSION: int = 1
const STAT_KEYS: PackedStringArray = ["encountered", "correct", "incorrect", "revisited", "skipped", "option_shown", "assisted", "unaided"]

var lemma_stats: Dictionary = {}
var scenario_log: Dictionary = {}
var current_day: int = 1
var days_finished: Array[int] = []
var onboarding_seen: bool = false


func reset() -> void:
	lemma_stats = {}
	scenario_log = {}
	current_day = 1
	days_finished = []
	onboarding_seen = false


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
	var log: Dictionary = _log_for(scenario)
	# Decided before the counters below, because the assisted/unaided split depends on it.
	var assisted: bool = bool(log.get("hint_used", false))
	for lemma_id: String in _string_array(scenario.get("target_lemma_ids", [])):
		var stats: Dictionary = _stats_for(lemma_id)
		if was_correct:
			stats["correct"] = int(stats["correct"]) + 1
			stats["assisted" if assisted else "unaided"] = int(stats["assisted" if assisted else "unaided"]) + 1
		else:
			stats["incorrect"] = int(stats["incorrect"]) + 1
	var attempts: int = int(log.get("attempts", 0)) + 1
	log["attempts"] = attempts
	if was_correct and not bool(log.get("solved", false)):
		log["solved"] = true
		log["first_correct_attempt"] = attempts
		# A translation that was open when the answer was given is never reported as unaided.
		log["solved_unaided"] = not assisted


## The player revealed the Russian meaning of this task, or the task is the guided example that
## reveals it on its own. Recording it here is what makes `unaided` mean something.
func mark_hint_used(scenario: Dictionary) -> void:
	var log: Dictionary = _log_for(scenario)
	log["hint_used"] = true


func hint_used(scenario_id: String) -> bool:
	return bool(scenario_entry(scenario_id).get("hint_used", false))


func has_seen_onboarding() -> bool:
	return onboarding_seen


func set_onboarding_seen(seen: bool) -> void:
	onboarding_seen = seen


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


## The end-of-day summary lines: the German word the player met, its Russian and English meaning,
## and what this run actually did with it. German stays the head word because German is what was
## practised.
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
		var gloss_ru: String = content.lemma_gloss_ru(lemma_id)
		var gloss_en: String = String(record.get("en", ""))
		var gloss: String = gloss_ru if gloss_en.is_empty() else "%s / %s" % [gloss_ru, gloss_en]
		var values: Dictionary = stats(lemma_id)
		lines.append("%s (%s) - %s %d, %s %d, %s %d, %s %d, %s %d, %s %d, %s %d" % [
			display, gloss,
			content.stat_label("met"), int(values["encountered"]),
			content.stat_label("correct"), int(values["correct"]),
			content.stat_label("incorrect"), int(values["incorrect"]),
			content.stat_label("repeat"), int(values["revisited"]),
			content.stat_label("skip"), int(values["skipped"]),
			content.stat_label("assisted"), int(values["assisted"]),
			content.stat_label("unaided"), int(values["unaided"]),
		])
	return lines


func save_run() -> bool:
	var document: Dictionary = {
		"version": SAVE_VERSION,
		"current_day": current_day,
		"days_finished": days_finished,
		"onboarding_seen": onboarding_seen,
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
	# A save written before onboarding existed simply has no key here, and loading such a save
	# must not fail: the player gets the briefing again.
	onboarding_seen = bool(parsed.get("onboarding_seen", false))
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
	var result: Dictionary = {"encountered": 0, "correct": 0, "incorrect": 0, "revisited": 0, "skipped": 0, "assisted": 0, "unaided": 0}
	for key: Variant in lemma_stats:
		var values: Dictionary = lemma_stats[key] as Dictionary
		for stat_key: String in result:
			result[stat_key] = int(result[stat_key]) + int(values.get(stat_key, 0))
	return result


## Scenario-level counters for the status line: one solved scenario counts one correct attempt,
## everything else the player tried counts as a wrong answer, and a solved scenario is counted
## once as assisted and once as unaided so the two can never be confused.
func scenario_totals() -> Dictionary:
	var solved: int = 0
	var solved_unaided: int = 0
	var solved_assisted: int = 0
	var skipped: int = 0
	var attempts: int = 0
	for key: Variant in scenario_log:
		var entry: Dictionary = scenario_log[key] as Dictionary
		attempts += int(entry.get("attempts", 0))
		if bool(entry.get("solved", false)):
			solved += 1
			if bool(entry.get("solved_unaided", false)):
				solved_unaided += 1
			else:
				solved_assisted += 1
		if bool(entry.get("skipped", false)):
			skipped += 1
	return {
		"solved": solved, "skipped": skipped, "attempts": attempts,
		"solved_unaided": solved_unaided, "solved_assisted": solved_assisted,
		"wrong_attempts": maxi(attempts - solved, 0),
	}


func _stats_for(lemma_id: String) -> Dictionary:
	if not lemma_stats.has(lemma_id):
		lemma_stats[lemma_id] = _empty_stats()
	return lemma_stats[lemma_id] as Dictionary


func _log_for(scenario: Dictionary) -> Dictionary:
	var id: String = String(scenario.get("id", "<no id>"))
	if not scenario_log.has(id):
		scenario_log[id] = {"attempts": 0, "solved": false, "skipped": false, "first_correct_attempt": 0, "hint_used": false, "solved_unaided": false}
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
