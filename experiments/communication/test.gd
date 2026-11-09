extends SceneTree
const Parser = preload("res://experiments/communication/parser.gd")
const Context = preload("res://experiments/communication/context.gd")
const Catalog = preload("res://experiments/communication/word_catalog.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func say(state, text: String, target := "") -> Dictionary:
	return state.respond(Parser.parse(text,target,state.parser_context()))

func snapshot(state) -> Array:
	return [state.opened,state.locked,state.key_location,state.permission,state.successes]

func _init() -> void:
	# Each row asserts the complete public decision and the safety-critical semantic slots.
	# text, status, intent, subject, object, polarity, speech act
	var rows := [
		["Ich will Schlüssel","RECOGNIZED","REQUEST_ITEM","player","key","positive","request"],
		["Ich will den Schlüssel","RECOGNIZED","REQUEST_ITEM","player","key","positive","request"],
		["Ich brauche Schlüssel","RECOGNIZED","REQUEST_ITEM","player","key","positive","request"],
		["Ich brauchen Schlüssel","RECOGNIZED","REQUEST_ITEM","player","key","positive","request"],
		["Schlüssel bitte","RECOGNIZED","REQUEST_ITEM","player","key","positive","request"],
		["Schlüssel?","NEEDS_CLARIFICATION","","unresolved","key","positive","question"],
		["Wo ist der Schlüssel?","RECOGNIZED","ASK_LOCATION","unresolved","key","positive","question"],
		["Wo Schlüssel?","RECOGNIZED","ASK_LOCATION","unresolved","key","positive","question"],
		["Ich habe keinen Schlüssel","RECOGNIZED","REPORT_PROBLEM","player","key","negative","statement"],
		["Anna hat keinen Schlüssel","RECOGNIZED","REPORT_STATE","anna","key","negative","statement"],
		["Ich kann die Tür nicht öffnen","RECOGNIZED","REPORT_PROBLEM","player","door","negative","statement"],
		["Ich will die Tür öffnen","RECOGNIZED","EXPRESS_DESIRE","player","door","positive","statement"],
		["Kannst du die Tür öffnen?","RECOGNIZED","REQUEST_ACTION","anna","door","positive","request"],
		["Kann ich die Tür öffnen?","RECOGNIZED","ASK_PERMISSION","player","door","positive","question"],
		["Öffne die Tür bitte","RECOGNIZED","REQUEST_ACTION","anna","door","positive","request"],
		["Öffne die Tür nicht","RECOGNIZED","PROHIBIT_ACTION","anna","door","negative","prohibition"],
		["Ich will nicht öffnen","RECOGNIZED","EXPRESS_DESIRE","player","","negative","statement"],
		["Ich will nicht, dass Anna die Tür öffnet","UNSUPPORTED","","player","","negative","statement"],
		["Kannst du mir helfen?","RECOGNIZED","REQUEST_HELP","anna","","positive","request"],
		["Hilf mir bitte","RECOGNIZED","REQUEST_HELP","anna","","positive","request"],
		["Helfen bitte","RECOGNIZED","REQUEST_HELP","anna","","positive","request"],
		["Warum ist die Tür zu?","RECOGNIZED","ASK_REASON","unresolved","door","positive","question"],
		["Ja","NEEDS_CLARIFICATION","","player","","positive","unresolved"],
		["Nein","NEEDS_CLARIFICATION","","player","","positive","unresolved"],
		["Das öffnen","NEEDS_CLARIFICATION","","unresolved","","positive","statement"],
		["Ich will Banane","UNKNOWN","","player","","unresolved","unresolved"],
		["will","NEEDS_CLARIFICATION","","player","","positive","statement"],
		["Ich will Schlüssel nicht","RECOGNIZED","EXPRESS_DESIRE","player","key","negative","statement"],
		["Du kannst die Tür öffnen","RECOGNIZED","REPORT_STATE","anna","door","positive","statement"],
		["Ich öffne die Tür","RECOGNIZED","REPORT_STATE","player","door","positive","statement"],
		["Anna will Schlüssel","RECOGNIZED","REPORT_STATE","anna","key","positive","statement"]
	]
	for row in rows:
		var r := Parser.parse(row[0])
		check([r.status,r.intent,r.frame.subject,r.frame.object_id,r.frame.polarity,r.frame.speech_act] == row.slice(1),"Matrix: %s -> %s" % [row[0],r])
		check(r.has("lexical_readings") and r.has("diagnostics") and r.has("unsupported_features"),"Contract: "+row[0])
		var state = Context.new()
		var before := snapshot(state)
		var out: Dictionary = state.respond(r)
		if r.status != "RECOGNIZED" or r.intent in ["PROHIBIT_ACTION","EXPRESS_DESIRE","REPORT_STATE","REPORT_PROBLEM","ASK_LOCATION","ASK_REASON"]:
			check(snapshot(state) == before and out.action == "","Unexpected effect: "+row[0])
	check("OMITTED_ARTICLE" in Parser.parse("ich will Schlüssel").diagnostics,"Missing article diagnostic")
	check("AGREEMENT_MISMATCH" in Parser.parse("ich brauchen Schlüssel").diagnostics,"Agreement diagnostic")
	check(Parser.parse("Ich habe keinen Schlüssel").frame.negation_scope == "object","Nominal negation scope")
	check(Parser.parse("Ich kann die Tür nicht öffnen").frame.negation_scope == "predicate","Predicate negation scope")
	check(Parser.parse("Ich will nicht, dass Anna die Tür öffnet").unsupported_features == ["SUBORDINATE_CLAUSE"],"Clause diagnostic")
	check(Parser.parse("Ich will Banane").diagnostics[0] == {"code":"UNKNOWN_TOKEN","token":"banane","position":9},"Unknown token preserves source position")
	var desire: Dictionary = Parser.parse("Ich will die Tür öffnen").frame
	check(desire.predicate == "want" and desire.modality == "want" and desire.action == "open" and desire.subject == "player","Linked modal/infinitive frame")
	var request: Dictionary = Parser.parse("Kannst du die Tür öffnen?").frame
	check(request.predicate == "can" and request.modality == "can" and request.action == "open" and request.subject == "anna","NPC performer frame")
	check(Parser.parse("Ich brauchen Schlüssel").frame.predicate == "need","Morphological normalization")
	check(Parser.parse("Ich will Schlüssel? dir").status == "UNSUPPORTED","Multiple clauses cannot become request")
	# Metamorphic tests vary form, object and politeness, never whole golden sentences.
	for article in ["","der ","die ","den ","das ","ein ","eine "]:
		for verb in ["will","brauche","brauchen"]:
			for suffix in [""," bitte"]:
				var r := Parser.parse("Ich "+verb+" "+article+"Schlüssel"+suffix)
				check(r.status == "RECOGNIZED" and r.intent == "REQUEST_ITEM" and r.frame.object_id == "key","Article/politeness/inflection invariance")
	for noun in ["Schlüssel","Tür","Zimmer"]:
		var a := Parser.parse("Ich will "+noun)
		var b := Parser.parse("Anna will "+noun)
		check(a.frame.subject == "player" and b.frame.subject == "anna" and b.intent == "REPORT_STATE","Subject substitution")
		check(a.frame.object_id == {"Schlüssel":"key","Tür":"door","Zimmer":"room"}[noun],"Object substitution")
		var neg := Parser.parse("Ich will "+noun+" nicht")
		check(neg.frame.polarity == "negative" and neg.intent != "REQUEST_ITEM","Negation mutation")
	for text in ["Ich will Banane","Öffne Banane bitte","Wo ist Banane?"]:
		var r := Parser.parse(text,"door")
		check(r.status == "UNKNOWN" and r.frame.object_id == "" and r.frame.target_id == "","Unknown object cannot inherit target")
	for text in ["Öffne die Tür bitte", "Kannst du die Tür öffnen", "Ich brauche Schlüssel", "Kannst du mir helfen"]:
		var neg := Parser.parse(text+" nicht")
		var world = Context.new()
		var before := snapshot(world)
		check(world.respond(neg).action == "" and snapshot(world) == before,"Negating an action cannot preserve its positive effect")
	var reference := Parser.parse("Das öffnen","door")
	check(reference.status == "NEEDS_CLARIFICATION" and reference.frame.object_id == "door" and reference.frame.action == "open","Partial pointed frame")
	check(Parser.parse("Was ist das?","key").intent == "IDENTIFY","Pointed identification")
	check(Parser.parse("Anna, ich will Schlüssel").frame.subject == "player","Vocative is not the subject")
	check(Parser.parse("Ich will den nicht Schlüssel").status == "NEEDS_CLARIFICATION","Unclear negation scope")
	for entry in Catalog.ENTRIES:
		check(entry.keys().size() == 6 and not Catalog.lookup(entry.surface).is_empty(),"Lexical contract")
		check(entry.surface in Parser.suggestions(entry.surface),"Recognized form must be typeable: "+entry.surface)
		check(Parser.parse(entry.surface).status in ["RECOGNIZED","NEEDS_CLARIFICATION","UNSUPPORTED"],"Catalog surface classified: "+entry.surface)
	check(Catalog.lookup("das").size() == 2 and Catalog.lookup("öffne").size() == 2,"Keep all lexical readings")
	check("will" in Parser.suggestions("wi") and "dir" in Parser.suggestions("di"),"Required input forms")
	check(Parser.suggestions("sch") == ["Schlüssel"],"Case-insensitive prefix")
	check(Parser.parse("ICH\tWILL\nSCHLÜSSEL!").intent == "REQUEST_ITEM","Unicode whitespace and case")
	# Resolver integration: ownership, availability, knowledge and idempotence.
	var state = Context.new()
	check(say(state,"Ich will Schlüssel").action == "give","Want -> actual transfer")
	check(say(state,"Ich will Schlüssel").action == "" and state.key_location == "player","Repeat transfer is inert")
	check(state.open_door("player") and not state.open_door("player") and state.successes == 1,"Exactly one open")
	state = Context.new()
	state.key_location = "world"
	check(say(state,"Ich will Schlüssel").action == "" and state.key_location == "world","No phantom key")
	state.available = false
	check(say(state,"Ich will Schlüssel").text == "Später, bitte.","Busy response")
	state.knows = false
	check(say(state,"Wo ist der Schlüssel?").point == "","Unknown location has no pointing")
	state.knows = true
	check(say(state,"Wo ist der Schlüssel?").point == "key","Known location")
	state = Context.new()
	check(say(state,"Schlüssel?").action == "" and state.pending == "key_intent","Clarify before effects")
	check(say(state,"Ich will Schlüssel").action == "give","Continue clarification")
	state = Context.new()
	check(say(state,"Ich habe keinen Schlüssel").action == "" and state.key_location == "anna","Problem is not transfer")
	var answer := Parser.parse("Ja","",state.parser_context())
	check(answer.status == "RECOGNIZED" and answer.intent == "ACCEPT","Active offer yes")
	check(state.respond(answer).action == "open","Accept help offer")
	check(state.respond(answer).action == "","Expired acceptance callback")
	state = Context.new()
	say(state,"Ich habe keinen Schlüssel")
	check(Parser.parse("Nein","",state.parser_context()).intent == "REFUSE","Active offer no")
	check(say(state,"Nein").action == "" and state.pending == "","Refuse offer")
	state = Context.new()
	check(say(state,"Helfen bitte").action == "" and state.pending == "help_target","Help requires target")
	check(say(state,"Tür").action == "open","Context resolves reference, not speech act")
	state = Context.new()
	check(say(state,"Kannst du die Tür öffnen?").action == "open","Explicit NPC action")
	check(state.open_door("anna") and not state.open_door("anna"),"NPC opens once")
	check(say(state,"Kannst du die Tür öffnen?").action == "","No second NPC action after opening")
	state = Context.new()
	state.may_grant = false
	check(say(state,"Kann ich die Tür öffnen?").action == "" and not state.permission,"Permission denied")
	check(say(state,"Kannst du die Tür öffnen?").action == "","No unauthorized NPC opening")
	state.may_grant = true
	state.anna_access = false
	check(say(state,"Kannst du die Tür öffnen?").action == "","No NPC access")
	for text in ["Öffne die Tür nicht","Ich will nicht öffnen","Ich will Schlüssel nicht","Anna hat keinen Schlüssel","Ich will nicht, dass Anna die Tür öffnet","Banane öffnen","Das öffnen","Kannst du die Tür nicht öffnen?","Ich will die Tür öffnen"]:
		state = Context.new()
		var before := snapshot(state)
		check(say(state,text,"door").action == "" and snapshot(state) == before,"No unwanted world effect: "+text)
	# A forged legacy intent without recognized status cannot bypass the gate.
	state = Context.new()
	check(state.respond({"intent":"REQUEST_ITEM","target":"key"}).action == "" and state.key_location == "anna","Resolver status gate")
	var parsed := Parser.parse("Ich will Schlüssel")
	var original := parsed.duplicate(true)
	var state2 = Context.new()
	check(state.respond(parsed) == state2.respond(parsed) and snapshot(state) == snapshot(state2),"Deterministic resolver")
	check(parsed == original,"Resolver does not change the meaning of the frame")
	print("LANGUAGE_PARSER_SPEC: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("COMMUNICATION_PARSER_CONTEXT_PASS")
	quit(1 if failures else 0)
