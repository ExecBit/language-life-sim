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
## Parser diagnostic code -> oracle linguistic error category. This is evidence of
## a diagnosed grammatical error, not by itself proof of successful recovery.
## One mapping table makes parser evidence and oracle terminology explicit.
## Empty parser_codes mean the current parser has no diagnostic for that error.
const RECOVERY_ERROR_MAP := {
	"VERB_AGREEMENT":{"parser_codes":["AGREEMENT_MISMATCH"],"oracle_codes":["AGREEMENT_MISMATCH","VERB_AGREEMENT"]},
	"MISSING_FINITE_VERB":{"parser_codes":["OMITTED_COPULA"],"oracle_codes":["OMITTED_COPULA","MISSING_FINITE_VERB"]},
	"OMITTED_SUBJECT":{"parser_codes":["OMITTED_SUBJECT"],"oracle_codes":["OMITTED_SUBJECT","MISSING_SUBJECT","OMITTED_PRONOUN"]},
	"OMITTED_ARTICLE":{"parser_codes":["OMITTED_ARTICLE"],"oracle_codes":["OMITTED_ARTICLE"]},
	"ARTICLE_MISMATCH":{"parser_codes":["ARTICLE_MISMATCH"],"oracle_codes":["ARTICLE_MISMATCH"]},
	"WORD_ORDER":{"parser_codes":[],"oracle_codes":["WORD_ORDER"]},
	"PRONOUN_CASE":{"parser_codes":[],"oracle_codes":["PRONOUN_CASE"]},
	"MISSING_MODAL":{"parser_codes":[],"oracle_codes":["MISSING_MODAL"]},
	"INFINITIVE_FOR_FINITE":{"parser_codes":[],"oracle_codes":["INFINITIVE_FOR_FINITE"]},
	"TYPO_OR_NEAR_FORM":{"parser_codes":[],"oracle_codes":["TYPO_OR_NEAR_FORM"]},
	"OMITTED_MODAL":{"parser_codes":[],"oracle_codes":["OMITTED_MODAL"]},
	"FINITE_VERB_AFTER_MODAL":{"parser_codes":[],"oracle_codes":["FINITE_VERB_AFTER_MODAL"]},
	"OMITTED_SUBJECT_OR_VERB":{"parser_codes":[],"oracle_codes":["OMITTED_SUBJECT_OR_VERB"]},
	"MULTIPLE_RECOVERABLE_ERRORS":{"parser_codes":[],"oracle_codes":["MULTIPLE_RECOVERABLE_ERRORS"]},
	"REDUNDANT_INFINITIVE":{"parser_codes":[],"oracle_codes":["REDUNDANT_INFINITIVE"]},
	"MISSING_OBJECT":{"parser_codes":[],"oracle_codes":["MISSING_OBJECT"]},
	"LEXICAL_CALQUE":{"parser_codes":[],"oracle_codes":["LEXICAL_CALQUE"]}
}
## These are valid oracle annotations, but they are not grammatical-error
## categories and must never count as grammatical recovery evidence.
const NON_GRAMMATICAL_ORACLE_DIAGNOSTICS := {
	"AMBIGUOUS_REFERENCE":"SEMANTIC_AMBIGUITY",
	"AMBIGUOUS_SPEECH_ACT":"SEMANTIC_AMBIGUITY",
	"CLARIFY_AMBIGUOUS_HELP_ROLES":"SEMANTIC_AMBIGUITY",
	"CLARIFY_AMBIGUOUS_ROLES":"SEMANTIC_AMBIGUITY",
	"CLARIFY_CONFLICTING_PRONOUNS":"SEMANTIC_AMBIGUITY",
	"CLARIFY_ELLIPTIC_YES_NO":"SEMANTIC_AMBIGUITY",
	"CLARIFY_MISSING_SUBJECT":"SEMANTIC_AMBIGUITY",
	"CLARIFY_MULTIPLE_INTENTS":"SEMANTIC_AMBIGUITY",
	"CLARIFY_NAME_OR_STATE":"SEMANTIC_AMBIGUITY",
	"CLARIFY_QUESTION_OR_STATEMENT":"SEMANTIC_AMBIGUITY",
	"CLARIFY_UNCLEAR_NEGATION_SCOPE":"SEMANTIC_AMBIGUITY",
	"CLARIFY_UND_DU_CONTEXT":"SEMANTIC_AMBIGUITY",
	"CLARIFY_WHY_CONTEXT":"SEMANTIC_AMBIGUITY",
	"CONTRADICTORY_CLAUSES":"SEMANTIC_AMBIGUITY",
	"MISSING_CONTEXT":"SEMANTIC_AMBIGUITY",
	"UNKNOWN_TOKEN":"UNKNOWN_VOCABULARY",
	"UNSUPPORTED_DOMAIN":"UNSUPPORTED_FEATURE",
	"MULTIPLE_INTENTS":"UNSUPPORTED_FEATURE"
}
const NON_RECOVERY_DIAGNOSTICS := ["UNKNOWN_TOKEN", "SOCIAL_PREFIX", "CONTEXTUAL_TARGET"]

var structural_failures: Array[String] = []
var all_results: Array[Dictionary] = []
var ids: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	structural_failures.append(message)
	push_error("CORPUS FAIL: " + message)

func run() -> void:
	_test_recovery_contract()
	var counts := {"dev": {}, "validation": {}}
	for corpus_path in CORPUS_FILES:
		_load_split(corpus_path, counts)
	_validate_distribution(counts)
	_test_fixture_recovery_contract()
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
	for key in ["decision", "intent", "actor", "recipient", "polarity", "speech_act", "recovery_used", "diagnostic_codes", "may_advance_objective", "expected_objectives"]:
		if not expected.has(key):
			_fail("%s missing expected.%s" % [item.get("id", ""), key])
	if not expected.get("diagnostic_codes", []) is Array:
		_fail("%s expected.diagnostic_codes must be an array" % item.get("id", ""))
	else:
		for diagnostic_code in expected.diagnostic_codes:
			if _oracle_diagnostic_class(str(diagnostic_code)) == "UNCLASSIFIED":
				_fail("%s has unclassified expected diagnostic code %s" % [item.get("id", ""), diagnostic_code])
	_validate_expected_recovery_contract(item)
	if not expected.get("expected_objectives", []) is Array:
		_fail("%s expected_objectives must be an array" % item.get("id", ""))
	if bool(expected.get("may_advance_objective", false)) != (not expected.get("expected_objectives", []).is_empty()):
		_fail("%s objective boolean disagrees with expected_objectives" % item.get("id", ""))
	if expected.get("decision", "") == "NEEDS_CLARIFICATION":
		if not expected.has("reason") or not expected.has("candidate_interpretations") or expected.candidate_interpretations.is_empty():
			_fail("%s clarification needs a reason and candidate interpretations" % item.get("id", ""))
	if expected.get("decision", "") == "UNKNOWN" and expected.get("unknown_tokens", []).is_empty():
		_fail("%s UNKNOWN case needs unknown_tokens" % item.get("id", ""))
	if expected.get("decision", "") == "UNSUPPORTED" and expected.get("unsupported_features", expected.get("unsupported_domain", "")).is_empty():
		_fail("%s UNSUPPORTED case needs an unsupported feature or domain" % item.get("id", ""))
	if expected.has("semantic_frames") and not expected.semantic_frames is Array:
		_fail("%s expected.semantic_frames must be an array" % item.get("id", ""))
	if str(expected.get("intent", "")) in ["OFFER_HELP", "REQUEST_HELP", "PLAYER_CANNOT_HELP", "DESCRIBE_HELP"]:
		if not expected.has("helper") or not expected.has("help_recipient"):
			_fail("%s help intent needs explicit helper and help_recipient roles" % item.get("id", ""))
		elif expected.get("helper", "") != expected.get("actor", "") or expected.get("help_recipient", "") != expected.get("recipient", ""):
			_fail("%s help roles must agree with actor/recipient action roles" % item.get("id", ""))
	for frame in expected.get("semantic_frames", []):
		if str(frame.get("intent", "")) in ["OFFER_HELP", "REQUEST_HELP", "PLAYER_CANNOT_HELP", "DESCRIBE_HELP"]:
			if not frame.has("helper") or not frame.has("help_recipient"):
				_fail("%s help semantic frame needs helper and help_recipient roles" % item.get("id", ""))
			elif frame.get("helper", "") != frame.get("actor", "") or frame.get("help_recipient", "") != frame.get("recipient", ""):
				_fail("%s help frame roles disagree with actor/recipient" % item.get("id", ""))
	if "MULTIPLE_INTENTS" in expected.get("unsupported_features", []):
		if expected.get("decision", "") != "UNSUPPORTED" or expected.get("intents", []).size() < 2 or expected.get("semantic_frames", []).size() < 2:
			_fail("%s MULTIPLE_INTENTS must preserve at least two component intents and semantic frames" % item.get("id", ""))

func _validate_expected_recovery_contract(item: Dictionary) -> void:
	var expected: Dictionary = item.get("expected", {})
	var decision := str(expected.get("decision", ""))
	var recovery_used := bool(expected.get("recovery_used", false))
	if expected.has("semantic_recovery_status"):
		var recovery_status := str(expected.semantic_recovery_status)
		if recovery_status not in ["COMPLETE", "PARTIAL", "NONE"]:
			_fail("%s has invalid semantic_recovery_status %s" % [item.get("id", ""), recovery_status])
		elif recovery_used != (recovery_status == "COMPLETE"):
			_fail("%s recovery_used must mean complete semantic recovery" % item.get("id", ""))
	if recovery_used and decision == "NEEDS_CLARIFICATION":
		_fail("%s cannot mark unresolved meaning as complete semantic recovery" % item.get("id", ""))
	if recovery_used and decision == "UNKNOWN":
		_fail("%s cannot mark unknown vocabulary as complete semantic recovery" % item.get("id", ""))
	if recovery_used and decision == "UNSUPPORTED":
		var frames: Array = expected.get("semantic_frames", [])
		var intents: Array = expected.get("intents", [])
		if "MULTIPLE_INTENTS" not in expected.get("unsupported_features", []) or expected.get("semantic_recovery_status", "") != "COMPLETE":
			_fail("%s can retain complete recovery while unsupported only for fully resolved MULTIPLE_INTENTS" % item.get("id", ""))
		if intents.size() < 2 or frames.size() != intents.size():
			_fail("%s complete multi-intent recovery needs one frame per intent" % item.get("id", ""))
		for frame in frames:
			if not _is_complete_semantic_frame(frame):
				_fail("%s complete multi-intent recovery frame lacks a semantic role, polarity or speech act" % item.get("id", ""))

func _oracle_diagnostic_class(code: String) -> String:
	for category in RECOVERY_ERROR_MAP:
		var mapping: Dictionary = RECOVERY_ERROR_MAP[category]
		if code in mapping.oracle_codes:
			return "GRAMMATICAL_ERROR"
	return str(NON_GRAMMATICAL_ORACLE_DIAGNOSTICS.get(code, "UNCLASSIFIED"))

func _is_complete_semantic_frame(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var frame: Dictionary = value
	for key in ["intent", "grammatical_subject", "actor", "recipient", "polarity", "speech_act"]:
		if not frame.has(key): return false
	if str(frame.intent).is_empty() or str(frame.grammatical_subject).is_empty() or str(frame.actor).is_empty():
		return false
	if str(frame.polarity) not in ["positive", "negative"]:
		return false
	if str(frame.speech_act) not in ["statement", "question", "offer", "request", "farewell"]:
		return false
	if str(frame.get("action", "")).to_lower() == "help" and str(frame.intent) not in ["OFFER_HELP", "REQUEST_HELP", "PLAYER_CANNOT_HELP", "DESCRIBE_HELP"]:
		return false
	if str(frame.intent) in ["OFFER_HELP", "REQUEST_HELP", "PLAYER_CANNOT_HELP", "DESCRIBE_HELP"]:
		if not frame.has("helper") or not frame.has("help_recipient"):
			return false
		if str(frame.helper).is_empty() or str(frame.help_recipient).is_empty():
			return false
	if str(frame.intent) in ["PLAYER_MOOD_GOOD", "PLAYER_MOOD_LOW", "ASTERA_MOOD_LOW"] and not frame.has("experiencer"):
		return false
	return true

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

func _test_fixture_recovery_contract() -> void:
	for case_id in ["B-007", "B-060", "B-073", "B-076", "B-080"]:
		var item := _find_case_id(case_id)
		var expected: Dictionary = item.get("expected", {})
		if item.is_empty() or expected.get("decision", "") != "UNSUPPORTED" or expected.get("recovery_used", false) != true or expected.get("semantic_recovery_status", "") != "COMPLETE":
			_fail("%s must retain complete semantic recovery for unsupported multi-intent" % case_id)
		if expected.get("semantic_frames", []).size() < 2:
			_fail("%s must carry all component semantic frames" % case_id)
		for frame in expected.get("semantic_frames", []):
			if not _is_complete_semantic_frame(frame):
				_fail("%s has an incomplete recovered semantic frame" % case_id)
	var clarification := _find_case_id("B-038")
	if clarification.is_empty() or clarification.expected.get("decision", "") != "NEEDS_CLARIFICATION" or clarification.expected.get("recovery_used", true) != false or clarification.expected.get("semantic_recovery_status", "") != "PARTIAL":
		_fail("B-038 must be partial recovery because speech act remains unresolved")
	for probe in [{"id":"B-004","code":"REDUNDANT_INFINITIVE"},{"id":"B-036","code":"MISSING_OBJECT"},{"id":"B-068","code":"LEXICAL_CALQUE"}]:
		var item := _find_case_id(probe.id)
		if item.is_empty() or probe.code not in item.get("expected", {}).get("diagnostic_codes", []):
			_fail("%s must retain the legitimate %s oracle error category" % [probe.id, probe.code])

func _find_case_id(case_id: String) -> Dictionary:
	for item in all_results:
		if str(item.get("id", "")) == case_id:
			return item
	return {}

func _find_case(input_text: String) -> Dictionary:
	for result in all_results:
		if str(result.input).to_lower() == input_text.to_lower():
			return result
	return {}

func _test_recovery_contract() -> void:
	var cases := [
		{"name":"clean recognized utterance has no recovery", "parsed":{"status":"RECOGNIZED","intent":"GREETING","semantic_recovery_status":"COMPLETE","frame":{"intent":"GREETING","grammatical_subject":"player","actor":"player","recipient":"astera","polarity":"positive","speech_act":"statement"},"diagnostics":[]}, "expected_codes":[], "used":false, "semantic_status":"COMPLETE","grammar_error":false,"coverage":"NO_GOLD_ERROR_EXPECTED"},
		{"name":"verified semantic roles plus grammatical evidence recover", "parsed":{"status":"RECOGNIZED","intent":"PLAYER_PLAN","semantic_recovery_status":"COMPLETE","frame":{"intent":"PLAYER_PLAN","grammatical_subject":"player","actor":"player","recipient":"astera","polarity":"positive","speech_act":"statement"},"diagnostics":["AGREEMENT_MISMATCH"]}, "expected_codes":["VERB_AGREEMENT"], "used":true, "semantic_status":"COMPLETE","grammar_error":true,"coverage":"FULL"},
		{"name":"grammatical error with ambiguous meaning is partial", "parsed":{"status":"NEEDS_CLARIFICATION","intent":"ASK_ACTIVITY","frame":{"intent":"ASK_ACTIVITY","subject":"player"},"ambiguity":["AMBIGUOUS_ROLES"],"diagnostics":["AGREEMENT_MISMATCH"]}, "expected_codes":["VERB_AGREEMENT"], "used":false, "semantic_status":"PARTIAL","grammar_error":true,"coverage":"FULL"},
		{"name":"grammar in fully reconstructed unsupported compound is complete", "parsed":{"status":"UNSUPPORTED","unsupported_features":["MULTIPLE_INTENTS"],"semantic_frame_coverage":"COMPLETE","intents":["PLAYER_NAME","ASK_BACK"],"semantic_frames":[{"intent":"PLAYER_NAME","grammatical_subject":"player","actor":"player","recipient":"","polarity":"positive","speech_act":"statement"},{"intent":"ASK_BACK","grammatical_subject":"player","actor":"player","recipient":"astera","polarity":"positive","speech_act":"question"}],"diagnostics":["AGREEMENT_MISMATCH"]}, "expected_codes":["VERB_AGREEMENT"], "used":true,"semantic_status":"COMPLETE","grammar_error":true,"coverage":"FULL"},
		{"name":"incomplete unsupported compound remains partial", "parsed":{"status":"UNSUPPORTED","unsupported_features":["MULTIPLE_INTENTS"],"intents":["PLAYER_NAME","ASK_BACK"],"semantic_frames":[{"intent":"PLAYER_NAME"}],"diagnostics":["AGREEMENT_MISMATCH"]}, "expected_codes":["VERB_AGREEMENT"], "used":false,"semantic_status":"PARTIAL","grammar_error":true,"coverage":"FULL"},
		{"name":"partial recognized frame does not imply recovery", "parsed":{"status":"RECOGNIZED","intent":"OFFER_HELP","frame":{"intent":"OFFER_HELP","subject":"player","action":"REPORT_STATE"},"diagnostics":["AGREEMENT_MISMATCH"]}, "expected_codes":["VERB_AGREEMENT"], "used":false,"semantic_status":"PARTIAL","grammar_error":true,"coverage":"FULL"},
		{"name":"known but unsupported parser mapping yields missing coverage", "parsed":{"status":"RECOGNIZED","intent":"ASK_ACTIVITY","diagnostics":[]}, "expected_codes":["WORD_ORDER"], "used":false,"semantic_status":"PARTIAL","grammar_error":false,"coverage":"MISSING"},
		{"name":"new grammatical categories remain explicit and unmapped", "parsed":{"status":"RECOGNIZED","intent":"ASK_ACTIVITY","diagnostics":[]}, "expected_codes":["REDUNDANT_INFINITIVE","MISSING_OBJECT","LEXICAL_CALQUE"], "used":false,"semantic_status":"PARTIAL","grammar_error":false,"coverage":"MISSING"},
		{"name":"unknown oracle category is explicit", "parsed":{"status":"RECOGNIZED","intent":"ASK_ACTIVITY","diagnostics":[]}, "expected_codes":["FUTURE_ORACLE_FLAG"], "used":false,"semantic_status":"PARTIAL","grammar_error":false,"coverage":"UNCLASSIFIED_ORACLE_DIAGNOSTICS","unclassified":["FUTURE_ORACLE_FLAG"]},
		{"name":"grammatical evidence is independent of semantic recovery", "parsed":{"status":"UNKNOWN","diagnostics":["AGREEMENT_MISMATCH"]}, "expected_codes":["VERB_AGREEMENT"], "used":false,"semantic_status":"NONE","grammar_error":true,"coverage":"FULL"}
	]
	for test_case in cases:
		var assessment := _assess_recovery(test_case.parsed, test_case.expected_codes)
		var passed: bool = bool(assessment.recovery_used) == bool(test_case.used) and str(assessment.semantic_recovery_status) == str(test_case.semantic_status) and bool(assessment.grammatical_error_detected) == bool(test_case.grammar_error) and str(assessment.diagnostic_coverage) == str(test_case.coverage)
		if test_case.has("unmapped"):
			passed = passed and _sorted_strings(assessment.unmapped_parser_diagnostics) == _sorted_strings(test_case.unmapped)
		if test_case.has("unclassified"):
			passed = passed and _sorted_strings(assessment.unclassified_oracle_diagnostics) == _sorted_strings(test_case.unclassified)
		if passed:
			print("PASS recovery contract: ", test_case.name)
		else:
			_fail("recovery contract test failed: %s → %s" % [test_case.name, JSON.stringify(assessment)])
	for code in ["REDUNDANT_INFINITIVE", "MISSING_OBJECT", "LEXICAL_CALQUE"]:
		if _oracle_diagnostic_class(code) != "GRAMMATICAL_ERROR" or _canonical_error_categories([code]).is_empty():
			_fail("missing explicit grammatical diagnostic registration: " + code)
	if not _is_complete_semantic_frame({"intent":"PLAYER_PLAN","grammatical_subject":"player","actor":"player","recipient":"astera","polarity":"positive","speech_act":"statement"}):
		_fail("a complete semantic frame with verified roles must pass completeness validation")

func _assess_recovery(parsed: Dictionary, expected_diagnostic_codes: Array, resolved_decision: String = "", resolver_reaction: String = "") -> Dictionary:
	var parser_codes := _diagnostic_codes(parsed.get("diagnostics", []))
	var detected_categories := _detected_error_categories(parser_codes)
	var grammatical_error_detected := not detected_categories.is_empty()
	var unmapped: Array[String] = []
	for code in parser_codes:
		if not _has_parser_diagnostic_mapping(code) and code not in NON_RECOVERY_DIAGNOSTICS:
			unmapped.append(code if not code.is_empty() else "<empty>")
	var expected_categories := _canonical_error_categories(expected_diagnostic_codes)
	var unclassified: Array[String] = []
	for code in expected_diagnostic_codes:
		if _oracle_diagnostic_class(str(code)) == "UNCLASSIFIED": unclassified.append(str(code))
	var coverage := "UNCLASSIFIED_ORACLE_DIAGNOSTICS" if not unclassified.is_empty() else "NO_GOLD_ERROR_EXPECTED"
	if not expected_categories.is_empty():
		var detected_set := {}
		for category in detected_categories: detected_set[category] = true
		var matched := 0
		var aggregate_partial := false
		for category in expected_categories:
			if category == "MULTIPLE_RECOVERABLE_ERRORS":
				if detected_categories.size() >= 2: matched += 1
				elif not detected_categories.is_empty(): aggregate_partial = true
			elif category == "OMITTED_SUBJECT_OR_VERB":
				var has_subject := detected_set.has("OMITTED_SUBJECT")
				var has_verb := detected_set.has("MISSING_FINITE_VERB")
				if has_subject and has_verb: matched += 1
				elif has_subject or has_verb: aggregate_partial = true
			elif detected_set.has(category):
				matched += 1
		if matched == expected_categories.size() and not aggregate_partial: coverage = "FULL"
		elif matched > 0 or aggregate_partial: coverage = "PARTIAL"
		else: coverage = "MISSING"
	elif unclassified.is_empty() and not detected_categories.is_empty():
		coverage = "UNEXPECTED_DETECTION"
	var semantic_status := "NONE"
	var effective_decision := resolved_decision if not resolved_decision.is_empty() else str(parsed.get("status", "UNKNOWN"))
	if str(parsed.get("semantic_recovery_status", "")) in ["COMPLETE", "PARTIAL", "NONE"]:
		semantic_status = str(parsed.semantic_recovery_status)
		if semantic_status == "COMPLETE":
			if effective_decision == "RECOGNIZED":
				if not _is_complete_semantic_frame(parsed.get("frame", {})): semantic_status = "PARTIAL"
			elif effective_decision == "UNSUPPORTED" and "MULTIPLE_INTENTS" in parsed.get("unsupported_features", []):
				var explicit_frames: Array = parsed.get("semantic_frames", [])
				var explicit_intents: Array = parsed.get("intents", [])
				var explicit_complete := explicit_frames.size() >= 2 and explicit_frames.size() == explicit_intents.size() and str(parsed.get("semantic_frame_coverage", "")) == "COMPLETE"
				for explicit_frame in explicit_frames:
					explicit_complete = explicit_complete and _is_complete_semantic_frame(explicit_frame)
				if not explicit_complete: semantic_status = "PARTIAL"
			elif effective_decision != "UNSUPPORTED":
				semantic_status = "PARTIAL"
	elif effective_decision == "UNSUPPORTED" and "MULTIPLE_INTENTS" in parsed.get("unsupported_features", []):
		var frames: Array = parsed.get("semantic_frames", [])
		var intents: Array = parsed.get("intents", [])
		var all_frames_complete := frames.size() >= 2 and frames.size() == intents.size() and str(parsed.get("semantic_frame_coverage", "")) == "COMPLETE"
		for frame in frames:
			all_frames_complete = all_frames_complete and _is_complete_semantic_frame(frame)
		semantic_status = "COMPLETE" if all_frames_complete else ("PARTIAL" if not frames.is_empty() or not intents.is_empty() else "NONE")
	elif effective_decision == "RECOGNIZED" and _is_complete_semantic_frame(parsed.get("frame", {})):
		semantic_status = "COMPLETE"
	elif effective_decision == "NEEDS_CLARIFICATION" or not parsed.get("ambiguity", []).is_empty() or resolver_reaction.begins_with("clarify") or resolver_reaction == "ask_why_clarification":
		semantic_status = "PARTIAL" if not str(parsed.get("semantic", parsed.get("intent", ""))).is_empty() or not parsed.get("frame", {}).is_empty() else "NONE"
	elif not str(parsed.get("semantic", parsed.get("intent", ""))).is_empty() or not parsed.get("frame", {}).is_empty():
		semantic_status = "PARTIAL"
	if not _unknown_tokens(parsed).is_empty() and semantic_status == "COMPLETE":
		semantic_status = "PARTIAL"
	var has_structured_flag: bool = parsed.has("recovery_used") or (parsed.get("recovery", null) is Dictionary and parsed.recovery.has("used"))
	var structured_used: Variant = parsed.get("recovery_used", parsed.get("recovery", {}).get("used", false))
	var used := semantic_status == "COMPLETE" and grammatical_error_detected
	var status := semantic_status
	if has_structured_flag:
		if not structured_used is bool:
			status = "INVALID_STRUCTURED_RECOVERY_FLAG"
			used = false
		else:
			used = semantic_status == "COMPLETE" and bool(structured_used) and grammatical_error_detected
	if semantic_status != "COMPLETE": used = false
	return {
		"recovery_used":used,
		"status":status,
		"semantic_recovery_status":semantic_status,
		"grammatical_error_detected":grammatical_error_detected,
		"source":"STRUCTURED_PARSER" if has_structured_flag else ("MAPPED_DIAGNOSTIC" if grammatical_error_detected else "NONE"),
		"parser_diagnostic_codes":parser_codes,
		"detected_error_categories":detected_categories,
		"expected_error_categories":expected_categories,
		"diagnostic_coverage":coverage,
		"unmapped_parser_diagnostics":unmapped,
		"unclassified_oracle_diagnostics":unclassified
	}

func _detected_error_categories(parser_codes: Array) -> Array[String]:
	var categories: Array[String] = []
	for category in RECOVERY_ERROR_MAP:
		var parser_mapping: Dictionary = RECOVERY_ERROR_MAP[category]
		for code in parser_codes:
			if code in parser_mapping.parser_codes and category not in categories:
				categories.append(category)
	categories.sort()
	return categories

func _canonical_error_categories(codes: Array) -> Array[String]:
	var categories: Array[String] = []
	for category in RECOVERY_ERROR_MAP:
		var oracle_mapping: Dictionary = RECOVERY_ERROR_MAP[category]
		for code in codes:
			if str(code) in oracle_mapping.oracle_codes and category not in categories:
				categories.append(category)
	categories.sort()
	return categories

func _has_parser_diagnostic_mapping(code: String) -> bool:
	for mapping in RECOVERY_ERROR_MAP.values():
		if code in mapping.parser_codes: return true
	return false

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
	var objectives_advanced: Array[String] = []
	for objective_id in context.objective_progress:
		if not bool(before_objectives.get(objective_id, false)) and bool(context.objective_progress.get(objective_id, false)):
			objectives_advanced.append(str(objective_id))
	var expected: Dictionary = item.expected
	var frame: Dictionary = parsed.get("frame", {})
	var decision := str(parsed.get("status", "UNKNOWN"))
	var intent := str(parsed.get("semantic", parsed.get("intent", "")))
	if decision == "RECOGNIZED" and intent.is_empty():
		intent = str(parsed.get("intent", ""))
	var recovery_assessment := _assess_recovery(parsed, expected.get("diagnostic_codes", []), decision, reaction)
	var actual := {
		"decision": decision,
		"intent": intent,
		"intents": parsed.get("intents", [intent] if not intent.is_empty() else []),
		"actor": _normalize_role(str(frame.get("subject", ""))),
		"recipient": _normalize_role(str(frame.get("recipient", frame.get("addressee", "")))),
		"grammatical_subject": _normalize_role(str(frame.get("subject", ""))),
		"experiencer": parsed.get("experiencer", null),
		"helper": parsed.get("helper", null),
		"help_recipient": parsed.get("help_recipient", null),
		"semantic_frames": parsed.get("semantic_frames", null),
		"semantic_role_reporting": {"grammatical_subject":"FRAME_SUBJECT", "experiencer":"PROVIDED" if parsed.has("experiencer") else "NOT_EXPOSED", "helper":"PROVIDED" if parsed.has("helper") else "NOT_EXPOSED", "help_recipient":"PROVIDED" if parsed.has("help_recipient") else "NOT_EXPOSED", "semantic_frames":"PROVIDED" if parsed.has("semantic_frames") else "NOT_EXPOSED"},
		"polarity": str(frame.get("polarity", "unresolved")),
		"speech_act": str(frame.get("speech_act", "unresolved")),
		"recovery_used": recovery_assessment.recovery_used,
		"semantic_recovery_status": recovery_assessment.semantic_recovery_status,
		"grammatical_error_detected": recovery_assessment.grammatical_error_detected,
		"recovery_status": recovery_assessment.status,
		"recovery_source": recovery_assessment.source,
		"detected_error_categories": recovery_assessment.detected_error_categories,
		"recovery_diagnostic_coverage": recovery_assessment.diagnostic_coverage,
		"unmapped_parser_diagnostics": recovery_assessment.unmapped_parser_diagnostics,
		"parser_diagnostic_codes": recovery_assessment.parser_diagnostic_codes,
		"may_advance_objective": objective_changed,
		"objectives_advanced": objectives_advanced,
		"reason": _first(parsed.get("ambiguity", [])),
		# The current parser does not expose candidate readings. Keep that
		# capability gap explicit; an empty list would falsely imply it did.
		"candidate_interpretations": parsed.get("candidate_interpretations", null),
		"candidate_reporting": "PROVIDED" if parsed.has("candidate_interpretations") else "NOT_EXPOSED",
		"semantic_frame": frame.duplicate(true),
		"referent": parsed.get("referent", ""),
		"unknown_tokens": _unknown_tokens(parsed),
		"unsupported_features": parsed.get("unsupported_features", []),
		"unsupported_domain": parsed.get("unsupported_domain", ""),
		"effects": effects,
		"answer": answer,
		"reaction": reaction,
		"emotion_state": emotion,
		"animation_id": animation,
		"world_context_after": context.duplicate(true)
	}
	var mismatch: Array[String] = []
	for key in ["decision", "intent", "actor", "recipient", "grammatical_subject", "experiencer", "helper", "help_recipient", "semantic_frames", "polarity", "speech_act", "recovery_used", "may_advance_objective", "referent", "intents"]:
		if expected.has(key) and expected[key] != actual[key]:
			mismatch.append(key)
	if not recovery_assessment.expected_error_categories.is_empty() and recovery_assessment.diagnostic_coverage != "FULL":
		mismatch.append("recovery_diagnostic_coverage")
	if not recovery_assessment.unmapped_parser_diagnostics.is_empty():
		mismatch.append("unmapped_parser_diagnostics")
	var candidate_status := "NOT_APPLICABLE"
	if expected.get("decision", "") == "NEEDS_CLARIFICATION":
		if actual.candidate_reporting == "NOT_EXPOSED":
			candidate_status = "UNSUPPORTED_BY_PARSER"
		elif _sorted_strings(expected.candidate_interpretations) == _sorted_strings(actual.candidate_interpretations):
			candidate_status = "MATCH"
		else:
			candidate_status = "MISMATCH"
		if candidate_status != "MATCH": mismatch.append("candidate_interpretations")
	actual["candidate_comparison"] = candidate_status
	var clarification_quality := "NOT_APPLICABLE"
	if expected.get("decision", "") == "NEEDS_CLARIFICATION":
		if decision != "NEEDS_CLARIFICATION":
			clarification_quality = "MISSED"
		elif not actual.candidate_reporting == "PROVIDED":
			clarification_quality = "INSUFFICIENT_CANDIDATES"
		elif expected.get("reason", "") != actual.reason or candidate_status == "MISMATCH":
			clarification_quality = "INCORRECT"
		else:
			clarification_quality = "CORRECT"
	actual["clarification_quality"] = clarification_quality
	var full_frame_match := mismatch.is_empty()
	if expected.has("unknown_tokens") and _sorted_strings(expected.unknown_tokens) != _sorted_strings(actual.unknown_tokens):
		mismatch.append("unknown_tokens")
	if expected.has("unsupported_features") and _sorted_strings(expected.unsupported_features) != _sorted_strings(actual.unsupported_features):
		mismatch.append("unsupported_features")
	if expected.has("unsupported_domain") and str(expected.unsupported_domain) != str(actual.get("unsupported_domain", "")):
		mismatch.append("unsupported_domain")
	if expected.has("expected_objectives") and _sorted_strings(expected.expected_objectives) != _sorted_strings(actual.objectives_advanced):
		mismatch.append("objectives_advanced")
	if expected.get("decision", "") == "NEEDS_CLARIFICATION" and expected.get("reason", "") != actual.reason:
		mismatch.append("reason")
	return {"id":item.get("id", ""), "group":item.get("group", ""), "pair_id":item.get("pair_id", ""), "split":item.get("split", ""), "phenomena":item.get("phenomena", []), "input":item.get("input", ""), "context":item.get("context", {}), "expected":expected, "actual":actual, "parse":parsed, "mismatches":mismatch, "full_semantic_frame_match":full_frame_match and mismatch.is_empty(), "rationale":item.get("rationale", "")}

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

func _new_recovery_metrics() -> Dictionary:
	return {"total":0,"expected_true":0,"actual_true":0,"true_positive":0,"false_positive":0,"false_negative":0,"true_negative":0,"expected_grammatical_error":0,"actual_grammatical_error":0,"semantic_recovery_status":{},"status_counts":{},"diagnostic_coverage":{},"unmapped_parser_diagnostics":{}}

func _update_recovery_metrics(metrics: Dictionary, result: Dictionary) -> void:
	var expected_used := bool(result.expected.get("recovery_used", false))
	var actual_used := bool(result.actual.get("recovery_used", false))
	metrics.total += 1
	if not _canonical_error_categories(result.expected.get("diagnostic_codes", [])).is_empty(): metrics.expected_grammatical_error += 1
	if bool(result.actual.get("grammatical_error_detected", false)): metrics.actual_grammatical_error += 1
	if expected_used: metrics.expected_true += 1
	if actual_used: metrics.actual_true += 1
	if expected_used and actual_used: metrics.true_positive += 1
	elif expected_used: metrics.false_negative += 1
	elif actual_used: metrics.false_positive += 1
	else: metrics.true_negative += 1
	var status := str(result.actual.get("recovery_status", "NOT_REPORTED"))
	metrics.status_counts[status] = int(metrics.status_counts.get(status, 0)) + 1
	var semantic_status := str(result.actual.get("semantic_recovery_status", "NONE"))
	metrics.semantic_recovery_status[semantic_status] = int(metrics.semantic_recovery_status.get(semantic_status, 0)) + 1
	var coverage := str(result.actual.get("recovery_diagnostic_coverage", "NOT_REPORTED"))
	metrics.diagnostic_coverage[coverage] = int(metrics.diagnostic_coverage.get(coverage, 0)) + 1
	for code in result.actual.get("unmapped_parser_diagnostics", []):
		metrics.unmapped_parser_diagnostics[code] = int(metrics.unmapped_parser_diagnostics.get(code, 0)) + 1

func _phenomenon_family(phenomenon: String) -> String:
	var code := phenomenon.to_upper()
	if code.contains("MULTIPLE_INTENTS"): return "UNSUPPORTED_MULTI_INTENT"
	if code in ["VERB_AGREEMENT", "AGREEMENT_MISMATCH", "OMITTED_COPULA", "MISSING_FINITE_VERB", "INFINITIVE_FOR_FINITE", "MISSING_MODAL", "OMITTED_MODAL", "OMITTED_SUBJECT", "OMITTED_PRONOUN", "MISSING_SUBJECT", "OMITTED_SUBJECT_OR_VERB", "WORD_ORDER", "PRONOUN_CASE", "TYPO_OR_NEAR_FORM", "FINITE_VERB_AFTER_MODAL", "OMITTED_ARTICLE", "ARTICLE_MISMATCH", "MULTIPLE_RECOVERABLE_ERRORS", "RECOVERABLE_WORD_ORDER", "ELLIPTICAL_COORDINATION", "REDUNDANT_INFINITIVE", "MISSING_OBJECT", "LEXICAL_CALQUE"]:
		return "GRAMMATICAL_ERROR"
	if code.contains("AMBIGUOUS") or code.contains("CONFLICTING") or code.contains("UNCLEAR") or code in ["QUESTION_OR_STATEMENT", "CONTRADICTORY_CLAUSES", "MISSING_CONTEXT"]:
		return "SEMANTIC_AMBIGUITY"
	if code in ["CONTEXT_DEPENDENT", "WHY_CONTEXT", "UND_DU_CONTEXT", "NAME_OR_STATE", "NPC_BUSY_MODE"] or code.ends_with("CONTEXT") or code.begins_with("E-"):
		return "CONTEXT_DEPENDENT"
	if code in ["UNKNOWN_CONTENT_WORD", "UNSUPPORTED_DOMAIN", "UNSUPPORTED_LONG_CHAIN"]:
		return "UNKNOWN_OR_UNSUPPORTED"
	return "OTHER"

func _summarize(results: Array[Dictionary]) -> Dictionary:
	var summary := {"total":results.size(), "by_group":{}, "by_split":{
		"dev":{"total":0,"decision_match":0,"intent_match":0,"full_semantic_frame_match":0,"confusion_matrix":{},"false_accept":0,"false_reject":0,"missed_clarification":0,"insufficient_clarification":0,"incorrect_clarification":0,"objective_advancement_mismatch":0,"recovery":_new_recovery_metrics()},
		"validation":{"total":0,"decision_match":0,"intent_match":0,"full_semantic_frame_match":0,"confusion_matrix":{},"false_accept":0,"false_reject":0,"missed_clarification":0,"insufficient_clarification":0,"incorrect_clarification":0,"objective_advancement_mismatch":0,"recovery":_new_recovery_metrics()}
	}, "by_oracle_decision":{}, "by_phenomenon_family":{}, "by_intent":{}, "by_phenomenon":{}, "confusion_matrix":{}, "recovery":_new_recovery_metrics(), "unmapped_parser_diagnostics":{}, "decision_match":0,"intent_match":0,"full_semantic_frame_match":0,"candidate_interpretations_not_exposed":0,"candidate_interpretation_mismatch":0,"false_accept":0, "false_reject":0, "role_mismatch":0, "role_swap":0, "false_offer_acceptance":0, "negative_help_as_offer":0, "polarity_mismatch":0, "negation_lost":0, "missed_clarification":0, "wrong_clarification_reason":0,"insufficient_clarification":0,"incorrect_clarification":0, "unknown_vs_unsupported":0, "objective_advancement_mismatch":0, "representative_errors":[]}
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
		_update_recovery_metrics(summary.recovery, result)
		_update_recovery_metrics(split_summary.recovery, result)
		for diagnostic_code in actual.get("unmapped_parser_diagnostics", []):
			summary.unmapped_parser_diagnostics[diagnostic_code] = int(summary.unmapped_parser_diagnostics.get(diagnostic_code, 0)) + 1
		var decision_key := ed
		if not summary.by_oracle_decision.has(decision_key):
			summary.by_oracle_decision[decision_key] = {"total":0,"decision_match":0,"expected_recovery":0,"actual_recovery":0,"observed_parser_decisions":{},"by_split":{}}
		var oracle_decision_summary: Dictionary = summary.by_oracle_decision[decision_key]
		oracle_decision_summary.total += 1
		if ed == ad: oracle_decision_summary.decision_match += 1
		if bool(expected.get("recovery_used", false)): oracle_decision_summary.expected_recovery += 1
		if bool(actual.get("recovery_used", false)): oracle_decision_summary.actual_recovery += 1
		oracle_decision_summary.observed_parser_decisions[ad] = int(oracle_decision_summary.observed_parser_decisions.get(ad, 0)) + 1
		if not oracle_decision_summary.by_split.has(result.split): oracle_decision_summary.by_split[result.split] = 0
		oracle_decision_summary.by_split[result.split] += 1
		if ed == ad:
			split_summary.decision_match += 1
			summary.decision_match += 1
		if not split_summary.confusion_matrix.has(ed):
			split_summary.confusion_matrix[ed] = {}
		split_summary.confusion_matrix[ed][ad] = int(split_summary.confusion_matrix[ed].get(ad, 0)) + 1
		if ed != "RECOGNIZED" and ad == "RECOGNIZED":
			split_summary.false_accept += 1
		if ed == "RECOGNIZED" and ad != "RECOGNIZED":
			split_summary.false_reject += 1
		if ed == "NEEDS_CLARIFICATION" and ad != "NEEDS_CLARIFICATION":
			split_summary.missed_clarification += 1
		if expected.get("intent", "") != "" and expected.get("intent", "") == actual.get("intent", ""):
			split_summary.intent_match += 1
			summary.intent_match += 1
		if result.get("full_semantic_frame_match", false):
			split_summary.full_semantic_frame_match += 1
			summary.full_semantic_frame_match += 1
		if ed == "NEEDS_CLARIFICATION":
			if actual.get("candidate_reporting", "") == "NOT_EXPOSED":
				summary.candidate_interpretations_not_exposed += 1
			if actual.get("candidate_comparison", "") == "MISMATCH":
				summary.candidate_interpretation_mismatch += 1
			if actual.get("clarification_quality", "") == "INSUFFICIENT_CANDIDATES":
				split_summary.insufficient_clarification += 1
				summary.insufficient_clarification += 1
			elif actual.get("clarification_quality", "") == "INCORRECT":
				split_summary.incorrect_clarification += 1
				summary.incorrect_clarification += 1
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
				summary.by_phenomenon[phenomenon_key] = {"total":0, "decision_match":0,"oracle_decisions":{},"parser_decisions":{},"expected_recovery":0,"actual_recovery":0,"recovery_coverage":{}}
			var phenomenon_summary: Dictionary = summary.by_phenomenon[phenomenon_key]
			phenomenon_summary.total += 1
			phenomenon_summary.oracle_decisions[ed] = int(phenomenon_summary.oracle_decisions.get(ed, 0)) + 1
			phenomenon_summary.parser_decisions[ad] = int(phenomenon_summary.parser_decisions.get(ad, 0)) + 1
			if bool(expected.get("recovery_used", false)): phenomenon_summary.expected_recovery += 1
			if bool(actual.get("recovery_used", false)): phenomenon_summary.actual_recovery += 1
			var coverage := str(actual.get("recovery_diagnostic_coverage", "NOT_REPORTED"))
			phenomenon_summary.recovery_coverage[coverage] = int(phenomenon_summary.recovery_coverage.get(coverage, 0)) + 1
			if ed == ad:
				phenomenon_summary.decision_match += 1
			var family := _phenomenon_family(phenomenon_key)
			if not summary.by_phenomenon_family.has(family):
				summary.by_phenomenon_family[family] = {"total":0,"oracle_decisions":{},"parser_decisions":{},"expected_recovery":0,"actual_recovery":0}
			var family_summary: Dictionary = summary.by_phenomenon_family[family]
			family_summary.total += 1
			family_summary.oracle_decisions[ed] = int(family_summary.oracle_decisions.get(ed, 0)) + 1
			family_summary.parser_decisions[ad] = int(family_summary.parser_decisions.get(ad, 0)) + 1
			if bool(expected.get("recovery_used", false)): family_summary.expected_recovery += 1
			if bool(actual.get("recovery_used", false)): family_summary.actual_recovery += 1
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
		if expected.get("actor", "") != "" and expected.get("actor", "") != actual.get("actor", "") or expected.get("recipient", "") != "" and expected.get("recipient", "") != actual.get("recipient", ""):
			summary.role_mismatch += 1
			if expected.get("actor", "") == actual.get("recipient", "") and expected.get("recipient", "") == actual.get("actor", ""):
				summary.role_swap += 1
		if expected.get("polarity", "") in ["negative", "positive"] and expected.get("polarity", "") != actual.get("polarity", ""):
			summary.polarity_mismatch += 1
			if (expected.get("polarity", "") == "negative" and actual.get("polarity", "") == "positive") or (expected.get("polarity", "") == "positive" and actual.get("polarity", "") == "negative"):
				summary.negation_lost += 1
		if ed == "NEEDS_CLARIFICATION" and ad != "NEEDS_CLARIFICATION":
			summary.missed_clarification += 1
		if ed == "NEEDS_CLARIFICATION" and ad == "NEEDS_CLARIFICATION" and expected.get("reason", "") != actual.get("reason", ""):
			summary.wrong_clarification_reason += 1
		if ed in ["UNKNOWN", "UNSUPPORTED"] and ad in ["UNKNOWN", "UNSUPPORTED"] and ed != ad:
			summary.unknown_vs_unsupported += 1
		if expected.get("may_advance_objective", false) != actual.get("may_advance_objective", false) or expected.has("expected_objectives") and _sorted_strings(expected.expected_objectives) != _sorted_strings(actual.objectives_advanced):
			summary.objective_advancement_mismatch += 1
			split_summary.objective_advancement_mismatch += 1
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

