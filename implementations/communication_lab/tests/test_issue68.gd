extends SceneTree
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const Graph = preload("res://implementations/communication_lab/game/communication/dialogue_graph.gd")
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const GraphView = preload("res://implementations/communication_lab/game/ui/dialogue_graph_view.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func send(context: Dictionary, action_id: String, sentence: String) -> Dictionary:
	var selection := Session.select_action(action_id, context)
	if not selection.get("accepted", false):
		check(false, "action available: " + action_id + " at " + Graph.node_id(context))
		return {}
	return Session.submit(sentence, context)

func new_session() -> Dictionary:
	var context := Session.initial_context()
	Session.opening_line(context)
	return context

func run() -> void:
	var authored := Graph.data()
	check(authored.nodes.size() == 18 and Graph.validate().is_empty(), "authored graph has 18 reachable nodes, stable edges, valid guards/effects and four terminal outcomes")
	check(authored.terminal_nodes == ["E_OFFICIAL", "E_FAVOR", "E_LEAVE", "E_CAUGHT"], "all four distinct endings are authored data")
	var initial := Session.initial_context()
	check(initial.current_node == "G00_GATE" and initial.roster_has_player and not initial.is_technician and not initial.has_pass and initial.access_status == "none" and initial.trust == "neutral" and not initial.message_promise and initial.pending_proposition.is_empty() and initial.dialogue_history.is_empty(), "runtime begins with the required RPG facts and an empty event history")

	# Path 1: honest introduction through the no-card exchange.
	var p1 := new_session()
	send(p1, "report_no_card", "Ich habe keine Karte.")
	send(p1, "report_newcomer", "Ich bin neu.")
	send(p1, "introduce", "Ich heiße Neral.")
	send(p1, "request_pass", "Kann ich einen Pass bekommen?")
	send(p1, "confirm_proposition", "Ja")
	check(p1.node_history == ["G00_GATE", "G10_NO_CARD", "G30_NAME", "G40_REGISTERED", "G50_CONFIRM", "E_OFFICIAL"] and p1.access_status == "official" and p1.has_pass and p1.player_name == "Neral", "path 1 reaches official access through the authored edge route")
	check(p1.dialogue_history.back().transition_id == "T_G50_CONFIRM" and p1.dialogue_history.back().effects.size() == 1 and p1.dialogue_history.back().active_conditions.size() > 0, "successful event stores transition id, actual facts, effects and evaluated conditions")

	# Path 2: ask the rules, introduce a free name and confirm the registry match.
	var p2 := new_session()
	send(p2, "ask_rules", "Wie komme ich rein?")
	send(p2, "introduce", "Ich bin Alex.")
	send(p2, "request_pass", "Ich möchte einen Pass.")
	send(p2, "confirm_proposition", "Ja")
	check(p2.node_history == ["G00_GATE", "G20_RULES", "G40_REGISTERED", "G50_CONFIRM", "E_OFFICIAL"] and p2.access_status == "official" and p2.player_name == "Alex", "path 2 reaches official access through the rules branch")

	# Path 3: accept the concrete message offer and confirm the task.
	var p3 := new_session()
	send(p3, "report_no_card", "Ich habe keine Karte.")
	send(p3, "ask_alternative", "Gibt es einen anderen Weg?")
	send(p3, "confirm_proposition", "Ja")
	send(p3, "confirm_proposition", "Ja")
	check(p3.node_history == ["G00_GATE", "G10_NO_CARD", "G90_DEAL", "G100_INSTRUCTION", "E_FAVOR"] and p3.access_status == "conditional" and p3.message_promise and p3.has_pass, "path 3 reaches conditional access only after confirming the message")

	# Path 4: a repeat request keeps the same proposition open at the simpler node.
	var p4 := new_session()
	send(p4, "report_no_card", "Ich hab keine Karte.")
	send(p4, "ask_alternative", "Gibt es einen anderen Weg?")
	send(p4, "confirm_proposition", "Ja")
	send(p4, "ask_repeat", "Kannst du das wiederholen?")
	check(p4.current_node == "G110_REPEAT" and p4.pending_proposition.id == "understands_message_for_tom", "path 4 repeat edge preserves the specific delivery proposition")
	send(p4, "confirm_proposition", "Ja")
	check(p4.node_history == ["G00_GATE", "G10_NO_CARD", "G90_DEAL", "G100_INSTRUCTION", "G110_REPEAT", "E_FAVOR"] and p4.message_promise, "path 4 reaches the favor ending after a repeat")

	# Path 5: a first false role claim is checked without punishment; admission restores the official path.
	var p5 := new_session()
	send(p5, "claim_technician", "Ich bin Techniker.")
	send(p5, "introduce", "Ich heiße Neral.")
	check(p5.current_node == "G70_EXPOSED" and p5.trust == "neutral" and not p5.has_pass, "first false technician claim is checked without changing trust or access")
	send(p5, "deny_technician", "Ich bin kein Techniker.")
	send(p5, "ask_official_path", "Bin ich registriert?")
	send(p5, "request_pass", "Kann ich einen Pass bekommen?")
	send(p5, "confirm_proposition", "Ja")
	check(p5.node_history == ["G00_GATE", "G60_TECHNICIAN", "G70_EXPOSED", "G20_RULES", "G40_REGISTERED", "G50_CONFIRM", "E_OFFICIAL"] and p5.access_status == "official" and p5.trust == "neutral", "path 5 admits the error and completes the official route")

	# Path 6: trust changes only after the contradiction is explicit and repeated.
	var p6 := new_session()
	send(p6, "claim_technician", "Ich bin Techniker.")
	send(p6, "introduce", "Ich heiße Neral.")
	send(p6, "claim_technician", "Ich bin Techniker.")
	check(p6.current_node == "G80_WARNING" and p6.trust == "suspicious" and p6.access_status == "none", "only deliberate insistence after exposure changes trust")
	send(p6, "claim_technician", "Ich bin Techniker.")
	check(p6.node_history == ["G00_GATE", "G60_TECHNICIAN", "G70_EXPOSED", "G80_WARNING", "E_CAUGHT"] and p6.access_status == "denied" and p6.trust == "suspicious", "path 6 reaches the caught ending after warning and continued deception")

	# Path 7: refusing the offer is not a punishment.
	var p7 := new_session()
	send(p7, "report_no_card", "Ich habe keine Karte.")
	send(p7, "ask_alternative", "Gibt es einen anderen Weg?")
	send(p7, "reject_proposition", "Nein")
	check(p7.current_node == "G120_REFUSED_DEAL" and p7.access_status == "none" and p7.trust == "neutral" and not p7.message_promise, "path 7 refusal has no punishment or hidden effects")
	send(p7, "farewell", "Tschüss.")
	check(p7.node_history == ["G00_GATE", "G10_NO_CARD", "G90_DEAL", "G120_REFUSED_DEAL", "E_LEAVE"], "path 7 ends with an unpunished departure")

	# Path 8: terminal reopening records a real system edge and never repeats an effect.
	for context in [p1, p3]:
		var old_effect_count := 0
		for event in context.dialogue_history: old_effect_count += event.effects.size()
		var returned := Session.opening_line(context)
		var expected_name := str(context.player_name) if not str(context.player_name).is_empty() else "Fremder"
		check(context.current_node == "G130_RETURN" and context.dialogue_history.back().transition_id.ends_with("REOPEN") and returned.answer.contains(expected_name), "terminal reopening follows an authored return edge and uses the known name or a neutral fallback")
		check(context.access_status in ["official", "conditional"] and context.message_promise == (context.access_status == "conditional"), "return line reflects access and message promise")
		var effects_after_return := 0
		for event in context.dialogue_history: effects_after_return += event.effects.size()
		var events_after_return: int = context.dialogue_history.size()
		Session.opening_line(context)
		check(effects_after_return == old_effect_count and context.current_node == "G130_RETURN" and context.dialogue_history.size() == events_after_return, "reopening again does not grant a duplicate effect or duplicate return event")

	# Productive language pairs, semantic counterexamples, and safe failure behavior.
	var no_card_a := Language.analyze_rpg("Ich habe keine Karte.", initial)
	var no_card_b := Language.analyze_rpg("Ich hab keinen Pass.", initial)
	var has_card := Language.analyze_rpg("Ich habe eine Karte.", initial)
	var other_person := Language.analyze_rpg("Du hast keine Karte.", initial)
	check(no_card_a.intent == "REPORT_NO_CARD" and no_card_b.intent == "REPORT_NO_CARD" and has_card.intent == "REPORT_HAS_CARD", "productive possession forms preserve positive versus negative pass meaning")
	check(other_person.status != "RECOGNIZED" or other_person.intent != "REPORT_NO_CARD", "second-person possession cannot report the player's missing card")
	var roles_a := Language.analyze_rpg("Kann ich dir helfen?", initial)
	var roles_b := Language.analyze_rpg("Kannst du mir helfen?", initial)
	check(roles_a.intent == "OFFER_HELP" and roles_a.frame.actor == "player" and roles_b.intent == "REQUEST_HELP" and roles_b.frame.actor == "astera", "help role reversal remains distinct")
	var tech_yes := Language.analyze_rpg("Ich bin ein Techniker.", initial)
	var tech_no := Language.analyze_rpg("Ich bin kein Techniker.", initial)
	check(tech_yes.intent == "CLAIM_TECHNICIAN" and tech_yes.frame.polarity == "positive" and tech_no.intent == "DENY_TECHNICIAN" and tech_no.frame.polarity == "negative", "role assertion and negation remain distinct across inflection")
	var unknown := Session.submit("Ich habe keine Karte, blorple", initial)
	check(unknown.parse.status == "UNKNOWN" and initial.current_node == "G00_GATE" and initial.trust == "neutral" and unknown.effects.is_empty() and unknown.transition_id.is_empty(), "unknown continuation cannot consume a recognized prefix or penalize the player")
	var compound := Session.submit("Ich habe keine Karte. Ich bin neu.", initial)
	check(compound.parse.status == "UNSUPPORTED" and initial.current_node == "G00_GATE" and compound.transition_id.is_empty(), "multiple intents are rejected as a whole")
	var yes_without_target := Session.submit("Ja", initial)
	check(yes_without_target.transition_id.is_empty() and initial.current_node == "G00_GATE" and yes_without_target.parse.reason == "NO_OPEN_YES_NO_TARGET", "a yes without a concrete open proposition cannot act")
	var menu_only := new_session()
	Session.select_action("report_no_card", menu_only)
	check(menu_only.current_node == "G00_GATE" and menu_only.access_status == "none" and menu_only.trust == "neutral", "choosing an action does not execute a plot effect")

	# Mismatched but valid intent requires confirmation before the authored edge can run.
	var mismatch := new_session()
	Session.select_action("ask_rules", mismatch)
	var first := Session.submit("Ich habe keine Karte.", mismatch)
	check(first.transition_id.is_empty() and mismatch.current_node == "G00_GATE" and not mismatch.pending_resolution.is_empty() and mismatch.access_status == "none", "valid sentence that differs from the selected goal waits without changing the graph")
	check(Session.available_actions(mismatch).map(func(a): return a.id) == ["confirm_proposition", "reject_proposition"], "safe mismatch offers only explicit confirm or reject actions")
	Session.select_action("confirm_proposition", mismatch)
	var confirmed := Session.submit("Ja", mismatch)
	check(confirmed.transition_id == "T_G00_NO_CARD" and mismatch.current_node == "G10_NO_CARD" and mismatch.access_status == "none" and confirmed.graph_event.actual_intent == "SHORT_YES" and confirmed.graph_event.resolved_intent == "REPORT_NO_CARD", "confirmation executes the previously understood edge and records both the yes and resolved intent")

	# F2 is native GraphEdit populated from the same 18-node, 61-edge resource.
	var view := GraphView.new()
	root.add_child(view)
	await process_frame
	view.set_snapshot(p2, -1)
	for frame in 8: await process_frame
	var edit: GraphEdit = view.graph_edit
	var rendered_nodes := 0
	for child in edit.get_children():
		if child is GraphNode: rendered_nodes += 1
	check(edit is GraphEdit and rendered_nodes == authored.nodes.size(), "F2 view creates one native GraphNode per runtime data node")
	check(edit.get_connection_list().size() == authored.transitions.size(), "F2 renders every authored runtime edge including inactive branches and loops")
	var compact_ports := true
	for node_id in authored.nodes:
		var card := edit.get_node(NodePath(str(node_id))) as GraphNode
		var outgoing_count := 0
		var incoming_count := 0
		for edge in authored.transitions:
			if str(edge.get("from", "")) == str(node_id): outgoing_count += 1
			if str(edge.get("to", "")) == str(node_id): incoming_count += 1
		if card == null or card.get_input_port_count() != incoming_count or card.get_output_port_count() != outgoing_count:
			compact_ports = false
	check(compact_ports, "F2 uses one compact incoming and outgoing port per authored transition")
	var expected_zoom_text := "%d%%" % roundi(edit.zoom * 100.0)
	check(not edit.show_zoom_buttons and view.zoom_label.text == expected_zoom_text, "F2 keeps graph controls outside the canvas and reports its actual zoom")
	var before_history: int = p2.dialogue_history.size()
	view.set_snapshot(p2.duplicate(true), 0)
	check(view.selected_attempt == 0 and p2.dialogue_history.size() == before_history and p2.current_node == "E_OFFICIAL", "historical graph snapshot is read-only")
	view.set_snapshot(p2, -1)
	check(view.current_node_id == "E_OFFICIAL" and view.node_history.size() == p2.node_history.size(), "live graph can return to current runtime state")
	view.queue_free()

	print("ISSUE68_TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
