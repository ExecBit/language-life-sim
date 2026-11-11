extends SceneTree
## Runs the frozen Issue #64 oracle against the existing parser/session path.
## Does not edit parser state or append to the player's user:// attempt journal.
const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const DialogueGrammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")

const CORPUS_FILES := [
	"res://implementations/communication_lab/tests/corpus/dev.jsonl",
	"res://implementations/communication_lab/tests/corpus/validation.jsonl"
]
const OUTPUT_DIR := "res://.local/issue64"
const EXPECTED_SPLITS := {
	"A": {"dev": 40, "validation": 10},
	"B": {"dev": 64, "validation": 16},
	"C": {"dev": 48, "validation": 12},
	"D": {"dev": 32, "validation": 8},
	"E": {"dev": 16, "validation": 4}
}
const RECOVERY_CODES := ["AGREEMENT_MISMATCH", "OMITTED_COPULA", "OMITTED_SUBJECT", "OMITTED_ARTICLE", "ARTICLE_MISMATCH"]

var structural_failures: Array[String] = []
var all_results: Array[Dictionary] = []
var ids: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	structural_failures.append(message)
	push_error("CORPUS FAIL: " + message)

func run() -> void:
	var counts := {"dev": {}, "validation": {}}
	for corpus_path in CORPUS_FILES:
		_load_split(corpus_path, counts)
	_validate_distribution(counts)
	_validate_required_probes()
	var summary := _summarize(all_results)
	_write_outputs(all_results, summary)
	print("ISSUE64_CORPUS_CASES: ", all_results.size())
	print("ISSUE64_CORPUS_DISTRIBUTION: ", JSON.stringify(counts))
	var console_summary := summary.duplicate(true)
	console_summary.erase("representative_errors")
	print("ISSUE64_BASELINE_METRICS: ", JSON.stringify(console_summary))
	if structural_failures.is_empty():
		print("ISSUE64_BASELINE_RUN: PASS (oracle mismatches are benchmark findings)")
		quit(0)
	else:
		print("ISSUE64_BASELINE_RUN: FAIL (%d corpus/runner integrity failures)" % structural_failures.size())
		quit(1)

func _load_split(corpus_path: String, counts: Dictionary) -> void:
	var file := FileAccess.open(corpus_path, FileAccess.READ)
	if file == null:
		_fail("cannot open " + corpus_path)
		return
	var split := "validation" if corpus_path.ends_with("validation.jsonl") else "dev"
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed_json: Variant = JSON.parse_string(line)
		if not parsed_json is Dictionary:
			_fail("%s contains invalid JSON: %s" % [corpus_path, line])
			continue
		var item: Dictionary = parsed_json
		if str(item.get("split", "")) != split:
			_fail("%s contains case with wrong split: %s" % [corpus_path, item.get("id", "" )])
		if str(item.get("id", "")).is_empty() or ids.has(item.get("id", "")):
			_fail("missing or duplicate case id: %s" % item.get("id", ""))
		else:
			ids[item.id] = true
		var group := str(item.get("group", ""))
		counts[split][group] = int(counts[split].get(group, 0)) + 1
		_validate_oracle_shape(item)
		all_results.append(_evaluate(item))

func _validate_oracle_shape(item: Dictionary) -> void:
	var expected: Dictionary = item.get("expected", {})
	for key in ["id", "group", "input", "context", "phenomena", "expected", "rationale"]:
		if not item.has(key):
			_fail("%s is missing required case field %s" % [item.get("id", "<no id>"), key])
	if str(item.get("rationale", "")).strip_edges().is_empty():
		_fail("%s needs a non-empty human-oracle rationale" % item.get("id", ""))
	if not item.get("context", {}) is Dictionary:
		_fail("%s context must be a dictionary" % item.get("id", ""))
	if str(item.get("group", "")) not in ["A", "B", "C", "D", "E"]:
		_fail("%s has invalid group %s" % [item.get("id", ""), item.get("group", "")])
	if str(expected.get("decision", "")) not in ["RECOGNIZED", "NEEDS_CLARIFICATION", "UNKNOWN", "UNSUPPORTED"]:
		_fail("%s has invalid expected decision %s" % [item.get("id", ""), expected.get("decision", "")])
	for key in ["decision", "intent", "actor", "recipient", "polarity", "speech_act", "recovery_used", "diagnostic_codes", "may_advance_objective"]:
		if not expected.has(key):
			_fail("%s missing expected.%s" % [item.get("id", ""), key])
	if expected.get("decision", "") == "NEEDS_CLARIFICATION":
		if not expected.has("reason") or not expected.has("candidate_interpretations") or expected.candidate_interpretations.is_empty():
			_fail("%s clarification needs a reason and candidate interpretations" % item.get("id", ""))
	if expected.get("decision", "") == "UNKNOWN" and expected.get("unknown_tokens", []).is_empty():
		_fail("%s UNKNOWN case needs unknown_tokens" % item.get("id", ""))
	if expected.get("decision", "") == "UNSUPPORTED" and expected.get("unsupported_features", expected.get("unsupported_domain", "")).is_empty():
		_fail("%s UNSUPPORTED case needs an unsupported feature or domain" % item.get("id", ""))

func _validate_distribution(counts: Dictionary) -> void:
	for split in ["dev", "validation"]:
		for group in EXPECTED_SPLITS:
			if int(counts[split].get(group, 0)) != int(EXPECTED_SPLITS[group][split]):
				_fail("%s/%s expected %d rows, found %d" % [split, group, EXPECTED_SPLITS[group][split], counts[split].get(group, 0)])
	if all_results.size() != 250:
		_fail("expected 250 cases, found %d" % all_results.size())
	var pairs: Dictionary = {}
	for result in all_results:
		if result.pair_id.is_empty():
			continue
		if not pairs.has(result.pair_id):
			pairs[result.pair_id] = []
		pairs[result.pair_id].append(result)
	if pairs.size() != 10:
		_fail("expected 10 contextual pairs, found %d" % pairs.size())
	for pair_id in pairs:
		if pairs[pair_id].size() != 2 or pairs[pair_id][0].input != pairs[pair_id][1].input:
			_fail("%s must contain exactly two context variants with the same utterance" % pair_id)

func _validate_required_probes() -> void:
	_check_expected("ich dir helfen", "RECOGNIZED", "OFFER_HELP")
	_check_expected("Ich mochtest helfe du", "NEEDS_CLARIFICATION", "")
	var ambiguous := _find_case("Ich mochtest helfe du")
	if ambiguous.is_empty() or ambiguous.expected.get("reason", "") != "AMBIGUOUS_ROLES":
		_fail("the exact role-ambiguity probe needs the AMBIGUOUS_ROLES oracle")
	_check_expected("Ich kann helfen.", "RECOGNIZED", "OFFER_HELP")
	_check_expected("Ich kann nicht helfen.", "RECOGNIZED", "PLAYER_CANNOT_HELP")
	var negated := _find_case("Ich kann nicht helfen.")
	if negated.is_empty() or negated.expected.get("polarity", "") != "negative":
		_fail("the negated-help probe must preserve negative polarity")
	_check_expected("Du mir helfen?", "RECOGNIZED", "REQUEST_HELP")
	var reverse_role := _find_case("Du mir helfen?")
	if reverse_role.is_empty() or reverse_role.expected.get("actor", "") != "astera" or reverse_role.expected.get("recipient", "") != "player":
		_fail("the reverse-role request must assign Astera as actor and player as recipient")
	_check_expected("Ich bin müde.", "RECOGNIZED", "PLAYER_MOOD_LOW")
	_check_expected("Du bist müde.", "RECOGNIZED", "ASTERA_MOOD_LOW")
	for text in ["Ja.", "Nein."]:
		var contextual := 0
		for result in all_results:
			if str(result.input).to_lower() == text.to_lower() and result.group == "E":
				contextual += 1
		if contextual < 2:
			_fail("E must include %s under at least two contexts" % text)
	var corpus_text := ""
	for result in all_results:
		corpus_text += str(result.input).to_lower() + "\n"
	if corpus_text.contains("schlüssel") or corpus_text.contains("tasse") or corpus_text.contains("tür"):
		_fail("corpus must remain within the conversation domain and exclude object interaction probes")

func _check_expected(input_text: String, decision: String, intent: String) -> void:
	var item := _find_case(input_text)
	if item.is_empty() or item.expected.get("decision", "") != decision or item.expected.get("intent", "") != intent:
		_fail("required oracle probe missing or mislabeled: %s → %s/%s" % [input_text, decision, intent])

func _find_case(input_text: String) -> Dictionary:
	for result in all_results:
		if str(result.input).to_lower() == input_text.to_lower():
			return result
	return {}

func _evaluate(item: Dictionary) -> Dictionary:
	var context := Session.initial_context()
	context.merge(item.get("context", {}), true)
	var extension_parse: Dictionary = DialogueGrammar.parse(str(item.input), context)
	var parsed: Dictionary
	var answer := ""
	var effects: Array[String] = []
	var reaction := "unrecognized"
	var emotion := "curious"
	var animation := "curious_head_tilt"
	if not extension_parse.is_empty():
		parsed = extension_parse
		var outcome: Dictionary = Session._resolve_dialogue(parsed, context)
		answer = outcome.answer
		reaction = outcome.reaction
		emotion = outcome.emotion_state
		animation = outcome.animation_id
	else:
		var parse_context := {"active": true, "pending": str(context.get("pending", "")), "addressee": "anna", "pointed_object_id": ""}
		parsed = Parser.parse(str(item.input), "", parse_context)
		answer = Session._resolve_legacy(parsed, context, effects)
		reaction = "legacy_%s" % str(parsed.get("intent", "unrecognized")).to_lower()
		var visual: Dictionary = Session._legacy_visuals(str(parsed.get("intent", "")), str(parsed.status))
		emotion = visual.emotion_state
		animation = visual.animation_id
	var before_objectives: Dictionary = context.objective_progress.duplicate(true)
	Session._update_objectives(parsed, context, reaction, str(item.input))
	var objective_changed: bool = before_objectives != context.objective_progress
	var expected: Dictionary = item.expected
	var diagnostics := _diagnostic_codes(parsed.get("diagnostics", []))
	var recovery := false
	for code in diagnostics:
		if code in RECOVERY_CODES:
			recovery = true
	var frame: Dictionary = parsed.get("frame", {})
	var decision := str(parsed.get("status", "UNKNOWN"))
	var intent := str(parsed.get("semantic", parsed.get("intent", "")))
	if decision == "RECOGNIZED" and intent.is_empty():
		intent = str(parsed.get("intent", ""))
	var actual := {
		"decision": decision,
		"intent": intent,
		"actor": _normalize_role(str(frame.get("subject", ""))),
		"recipient": _normalize_role(str(frame.get("recipient", frame.get("addressee", "")))),
		"polarity": str(frame.get("polarity", "unresolved")),
		"speech_act": str(frame.get("speech_act", "unresolved")),
		"recovery_used": recovery,
		"diagnostic_codes": diagnostics,
		"may_advance_objective": objective_changed,
		"reason": _first(parsed.get("ambiguity", [])),
		"candidate_interpretations": [],
		"unknown_tokens": _unknown_tokens(parsed),
		"unsupported_features": parsed.get("unsupported_features", []),
		"effects": effects,
		"answer": answer,
		"reaction": reaction,
		"emotion_state": emotion,
		"animation_id": animation,
		"world_context_after": context.duplicate(true)
	}
	var mismatch: Array[String] = []
	for key in ["decision", "intent", "actor", "recipient", "polarity", "speech_act", "recovery_used", "diagnostic_codes", "may_advance_objective"]:
		if expected.has(key) and expected[key] != actual[key]:
			mismatch.append(key)
	if expected.has("unknown_tokens") and _sorted_strings(expected.unknown_tokens) != _sorted_strings(actual.unknown_tokens):
		mismatch.append("unknown_tokens")
	if expected.get("decision", "") == "NEEDS_CLARIFICATION" and expected.get("reason", "") != actual.reason:
		mismatch.append("reason")
	return {"id":item.get("id", ""), "group":item.get("group", ""), "pair_id":item.get("pair_id", ""), "split":item.get("split", ""), "phenomena":item.get("phenomena", []), "input":item.get("input", ""), "context":item.get("context", {}), "expected":expected, "actual":actual, "parse":parsed, "mismatches":mismatch, "rationale":item.get("rationale", "")}

func _diagnostic_codes(raw: Variant) -> Array:
	var codes: Array = []
	for diagnostic in raw:
		if diagnostic is Dictionary:
			if str(diagnostic.get("code", "")) != "LAB_DIALOGUE_GRAMMAR":
				codes.append(str(diagnostic.get("code", "")))
		else:
			if str(diagnostic) != "LAB_DIALOGUE_GRAMMAR":
				codes.append(str(diagnostic))
	return codes

func _unknown_tokens(parsed: Dictionary) -> Array:
	var tokens: Array = []
	for diagnostic in parsed.get("diagnostics", []):
		if diagnostic is Dictionary and diagnostic.get("code", "") == "UNKNOWN_TOKEN":
			tokens.append(str(diagnostic.get("token", "")))
	return tokens

func _first(values: Variant) -> String:
	return str(values[0]) if values is Array and not values.is_empty() else ""

func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	result.sort()
	return result

func _normalize_role(role: String) -> String:
	return "astera" if role == "anna" else role

func _summarize(results: Array[Dictionary]) -> Dictionary:
	var summary := {"total":results.size(), "by_group":{}, "by_split":{
		"dev":{"total":0,"decision_match":0,"confusion_matrix":{},"false_accept":0,"false_reject":0,"missed_clarification":0},
		"validation":{"total":0,"decision_match":0,"confusion_matrix":{},"false_accept":0,"false_reject":0,"missed_clarification":0}
	}, "by_intent":{}, "by_phenomenon":{}, "confusion_matrix":{}, "false_accept":0, "false_reject":0, "role_mismatch":0, "role_swap":0, "false_offer_acceptance":0, "negative_help_as_offer":0, "polarity_mismatch":0, "negation_lost":0, "missed_clarification":0, "wrong_clarification_reason":0, "unknown_vs_unsupported":0, "objective_advancement_mismatch":0, "representative_errors":[]}
	for result in results:
		var expected: Dictionary = result.expected
		var actual: Dictionary = result.actual
		var group: String = result.group
		if not summary.by_group.has(group):
			summary.by_group[group] = {"total":0, "decision_match":0, "intent_match":0, "mismatches":0}
		var group_summary: Dictionary = summary.by_group[group]
		group_summary.total += 1
		var ed := str(expected.get("decision", ""))
		var ad := str(actual.get("decision", ""))
		var split_summary: Dictionary = summary.by_split[str(result.split)]
		split_summary.total += 1
		if ed == ad:
			split_summary.decision_match += 1
		if not split_summary.confusion_matrix.has(ed):
			split_summary.confusion_matrix[ed] = {}
		split_summary.confusion_matrix[ed][ad] = int(split_summary.confusion_matrix[ed].get(ad, 0)) + 1
		if ed != "RECOGNIZED" and ad == "RECOGNIZED":
			split_summary.false_accept += 1
		if ed == "RECOGNIZED" and ad != "RECOGNIZED":
			split_summary.false_reject += 1
		if ed == "NEEDS_CLARIFICATION" and ad != "NEEDS_CLARIFICATION":
			split_summary.missed_clarification += 1
		if not summary.confusion_matrix.has(ed):
			summary.confusion_matrix[ed] = {}
		summary.confusion_matrix[ed][ad] = int(summary.confusion_matrix[ed].get(ad, 0)) + 1
		var intent_key := str(expected.get("intent", ""))
		if intent_key.is_empty():
			intent_key = "NO_INTENT_%s" % ed
		if not summary.by_intent.has(intent_key):
			summary.by_intent[intent_key] = {"total":0, "decision_match":0, "intent_match":0, "observed_decisions":{}}
		var intent_summary: Dictionary = summary.by_intent[intent_key]
		intent_summary.total += 1
		if ed == ad:
			intent_summary.decision_match += 1
		if not str(expected.get("intent", "")).is_empty() and expected.get("intent", "") == actual.get("intent", ""):
			intent_summary.intent_match += 1
		intent_summary.observed_decisions[ad] = int(intent_summary.observed_decisions.get(ad, 0)) + 1
		for phenomenon in result.phenomena:
			var phenomenon_key := str(phenomenon)
			if not summary.by_phenomenon.has(phenomenon_key):
				summary.by_phenomenon[phenomenon_key] = {"total":0, "decision_match":0}
			var phenomenon_summary: Dictionary = summary.by_phenomenon[phenomenon_key]
			phenomenon_summary.total += 1
			if ed == ad:
				phenomenon_summary.decision_match += 1
		if ed == ad:
			group_summary.decision_match += 1
		if ed == "RECOGNIZED" or ad == "RECOGNIZED":
			group_summary.intent_compared = int(group_summary.get("intent_compared", 0)) + 1
			if not str(expected.get("intent", "")).is_empty() and expected.get("intent", "") == actual.get("intent", ""):
				group_summary.intent_match += 1
		if not result.mismatches.is_empty():
			group_summary.mismatches += 1
		if ed != "RECOGNIZED" and ad == "RECOGNIZED":
			summary.false_accept += 1
		if expected.get("intent", "") != "OFFER_HELP" and actual.get("intent", "") == "OFFER_HELP":
			summary.false_offer_acceptance += 1
			if expected.get("polarity", "") == "negative" and result.input.to_lower().contains("nicht"):
				summary.negative_help_as_offer += 1
		if ed == "RECOGNIZED" and ad != "RECOGNIZED":
			summary.false_reject += 1
		if ed == "RECOGNIZED" and ad == "RECOGNIZED" and (expected.get("actor", "") != actual.get("actor", "") or expected.get("recipient", "") != actual.get("recipient", "")):
			summary.role_mismatch += 1
			if expected.get("actor", "") == actual.get("recipient", "") and expected.get("recipient", "") == actual.get("actor", ""):
				summary.role_swap += 1
		if ed == "RECOGNIZED" and ad == "RECOGNIZED" and expected.get("polarity", "") in ["negative", "positive"] and expected.get("polarity", "") != actual.get("polarity", ""):
			summary.polarity_mismatch += 1
			if (expected.get("polarity", "") == "negative" and actual.get("polarity", "") == "positive") or (expected.get("polarity", "") == "positive" and actual.get("polarity", "") == "negative"):
				summary.negation_lost += 1
		if ed == "NEEDS_CLARIFICATION" and ad != "NEEDS_CLARIFICATION":
			summary.missed_clarification += 1
		if ed == "NEEDS_CLARIFICATION" and ad == "NEEDS_CLARIFICATION" and expected.get("reason", "") != actual.get("reason", ""):
			summary.wrong_clarification_reason += 1
		if ed in ["UNKNOWN", "UNSUPPORTED"] and ad in ["UNKNOWN", "UNSUPPORTED"] and ed != ad:
			summary.unknown_vs_unsupported += 1
		if expected.get("may_advance_objective", false) != actual.get("may_advance_objective", false):
			summary.objective_advancement_mismatch += 1
		if not result.mismatches.is_empty():
			summary.representative_errors.append(result)
	# Keep the highest-risk findings first and cap the human-readable report.
	summary.representative_errors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _error_risk(a) > _error_risk(b)
	)
	if summary.representative_errors.size() > 25:
		summary.representative_errors.resize(25)
	var compact_errors: Array[Dictionary] = []
	for result in summary.representative_errors:
		compact_errors.append({"id":result.id, "group":result.group, "input":result.input, "context":result.context,
			"expected":result.expected, "actual":result.actual, "mismatches":result.mismatches, "rationale":result.rationale})
	summary.representative_errors = compact_errors
	return summary

func _error_risk(result: Dictionary) -> int:
	var score := 0
	if "role_swap" in result.mismatches or "recipient" in result.mismatches: score += 10
	if "polarity" in result.mismatches: score += 10
	if result.expected.get("decision", "") == "NEEDS_CLARIFICATION" and result.actual.get("decision", "") == "RECOGNIZED": score += 8
	if "decision" in result.mismatches: score += 4
	return score

func _write_outputs(results: Array[Dictionary], summary: Dictionary) -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	var basename := "issue64-baseline"
	for split in ["dev", "validation"]:
		var file := FileAccess.open(output_path.path_join("%s-%s.jsonl" % [basename, split]), FileAccess.WRITE)
		if file == null:
			_fail("cannot write baseline results to " + output_path)
			return
		for result in results:
			if result.split == split:
				file.store_line(JSON.stringify(result))
	var summary_file := FileAccess.open(output_path.path_join("%s-summary.json" % basename), FileAccess.WRITE)
	if summary_file == null:
		_fail("cannot write summary to " + output_path)
		return
	summary_file.store_string(JSON.stringify(summary, "\t"))
