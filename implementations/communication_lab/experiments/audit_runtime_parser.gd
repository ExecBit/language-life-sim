extends SceneTree
## Diagnostic investigation only. Calls production entry points; does not change parser rules.
## No fixture/oracle data is read. Output stays under ignored .local/.
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const Grammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
var rows: Array = []
func send(c: Dictionary, action: String, text: String) -> void:
	Session.select_action(action, c)
	Session.submit(text, c)
func context_for(kind: String) -> Dictionary:
	var c := Session.initial_context()
	Session.opening_line(c)
	if kind == "registered":
		send(c, "report_no_card", "Ich habe keine Karte.")
		send(c, "report_newcomer", "Ich bin neu.")
		send(c, "introduce", "Ich heiße Alex.")
	elif kind == "exposed":
		send(c, "claim_technician", "Ich bin Techniker.")
		send(c, "introduce", "Ich heiße Alex.")
	elif kind == "instruction":
		send(c, "report_no_card", "Ich habe keine Karte.")
		send(c, "ask_alternative", "Gibt es einen anderen Weg?")
		send(c, "confirm_proposition", "Ja")
	return c
func probe(kind: String, action: String, text: String) -> void:
	var c := context_for(kind)
	var selection := Session.select_action(action, c)
	var before := c.duplicate(true)
	var r := Session.submit(text, c)
	var p: Dictionary = r.parse
	var row := {"text":text,"before":before.current_node,"requested_action":action,"selection_accepted":selection.get("accepted", false),"selected_action":before.selected_action,"status":p.status,"intent":p.intent,"reason":p.reason,"frame":p.frame,"recovery":p.get("semantic_recovery_status", ""),"inferred":p.get("inferred_fields", []),"node_after":c.current_node,"trust":c.trust,"access":c.access_status,"effects":r.effects,"reply":r.answer}
	rows.append(row)
	print("AUDIT ", JSON.stringify(row))
func _initialize() -> void:
	for text in ["Ich möchte einen Pass.", "Ich möchte einen vorläufigen Pass.", "Kann ich einen Pass bekommen?", "Darf ich einen Pass bekommen?", "Ich habe einen Pass.", "Ich möchte vorläufigen", "Ich möchte einen vorläufigen.", "Einen vorläufigen, bitte.", "Ich möchte keinen Pass.", "Ich möchte einen Pass nicht."]:
		probe("registered", "request_pass", text)
	for text in ["Ich bin Techniker.", "Techniker bin ich.", "Ich bin kein Techniker.", "Nein", "Ich bin Techniker nein", "Ich bin nein Techniker", "Ich bin Techniker, nein.", "Ich bin Techniker und helfe nicht.", "Ich bin kein Techniker und habe einen Pass.", "Ich bin Techniker, aber ich bin kein Techniker.", "Ich bin Techniker blorple"]:
		probe("exposed", "claim_technician", text)
	for text in ["Ich gebe Tom die Nachricht.", "Ich gebe Tom die Nachricht nicht.", "Ich möchte Tom die Nachricht nicht geben.", "Kannst du Tom eine Nachricht geben?", "Ich kann Tom die Nachricht geben?", "Ich gebe Tom die Nachricht, aber ich mache das nicht."]:
		probe("instruction", "confirm_proposition", text)
	for text in ["Kann ich dir helfen?", "Ich kann dir nicht helfen.", "Kannst du mir helfen?", "Ich helfe dir nicht.", "ich dir helfen", "Du hilfst mir."]:
		var old: Dictionary = Grammar.parse(text, {})
		var current: Dictionary = Language.analyze_rpg(text, Session.initial_context())
		var row := {"comparison":text,"legacy_status":old.get("status", ""),"legacy_intent":old.get("intent", ""),"legacy_frame":old.get("frame", {}),"runtime_status":current.status,"runtime_intent":current.intent,"runtime_frame":current.frame}
		rows.append(row)
		print("COMPARE ", JSON.stringify(row))
	var f := FileAccess.open("res://.local/parser-audit-results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	print("PARSER_AUDIT: %d observations; production code unchanged" % rows.size())
	quit()
