extends SceneTree
## LANGUAGE_PARSER_SPEC section 9: test parsing, reply and actual scene separately.
var scene
var results: Array = []
var failures := 0
var errors: Array[String] = []
var original_key_id := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)

func key_count(node: Node) -> int:
	var count := 1 if node.get_meta("target_id","") == "key" else 0
	for child in node.get_children(): count += key_count(child)
	return count

func world() -> Dictionary:
	return {"locked":scene.state.locked,"opened":scene.state.opened,
		"key_location":scene.state.key_location,"permission":scene.state.permission,
		"successes":scene.state.successes,"key_instance":scene.key.get_instance_id()}

func fresh(config: Dictionary = {}) -> void:
	scene.reset(0)
	for property in config: scene.state.set(property,config[property])
	scene.sync_world()
	scene.state.active = true
	scene.panel.show()
	scene.controls(true)
	errors.clear()
	await physics_frame
	await physics_frame

func submit(text: String) -> Dictionary:
	scene.state.active = true
	scene.phrase.text = text
	scene.submit()
	return scene.state.attempts[-1].duplicate(true)

func wait_for_action() -> void:
	var deadline := Time.get_ticks_msec()+5000
	while scene.action_running and Time.get_ticks_msec() < deadline: await process_frame
	check(not scene.action_running,"NPC action timed out")
	await physics_frame
	await physics_frame

func verify_world(owner: String, opened: bool, permission: bool) -> void:
	await physics_frame
	await physics_frame
	check(scene.state.key_location == owner,"Wrong key owner")
	var expected_parent: Node = {"anna":scene.anna.hand,"player":scene.hand,"world":scene.key_table}[owner]
	check(scene.key.get_parent() == expected_parent,"Visual key parent disagrees with ownership")
	check(scene.key.get_instance_id() == original_key_id and key_count(scene) == 1,"Key duplicated or replaced")
	check(scene.state.opened == opened and scene.state.locked != opened,"Door logical state")
	check(scene.collision.disabled == opened and scene.door.visible != opened,"Door collision/visibility")
	check(scene.state.permission == permission,"Unexpected permission change")
	check(scene.state.successes == (1 if opened else 0),"Duplicate opening event")
	# Verify actual blocking/passability, not just the collision flag.
	var saved_position: Vector3 = scene.player.position
	scene.player.position = Vector3(0,0.9,0)
	scene.player.move_and_collide(Vector3(0,0,-2))
	check((scene.player.position.z < -1) == opened,"Actual doorway collision disagrees with state")
	scene.player.position = saved_position

func frame_check(attempt: Dictionary, status: String, intent: String, subject: String, object_id: String, polarity: String, speech_act: String) -> void:
	var parsed: Dictionary = attempt.parse
	check([parsed.status,parsed.intent,parsed.frame.subject,parsed.frame.object_id,parsed.frame.polarity,parsed.frame.speech_act]
		== [status,intent,subject,object_id,polarity,speech_act],"Unexpected parse: "+str(parsed))

func record(id: String, text: String, attempt: Dictionary) -> void:
	var status := "PASS" if errors.is_empty() else "FAIL"
	if status == "FAIL": failures += 1
	results.append({"id":id,"status":status,"input":text,"parse":attempt.parse,
		"npc_reply":attempt.response,"world_before":attempt.world_before,
		"world_after_reply":attempt.world_after,"world_at_end":world(),"errors":errors.duplicate()})
	print("%s %s" % [id,status])
	errors.clear()

func run() -> void:
	scene = load("res://implementations/dormitory/experiments/communication/COMMUNICATION_EXPERIMENT.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	original_key_id = scene.key.get_instance_id()
	# R01/R02/R10 and W01: same meaning, independent resets for every utterance.
	for row in [["R01","Ich will Schlüssel"],["R02/a","Ich brauche den Schlüssel"],["R02/b","Schlüssel bitte"],["R10","Ich brauchen Schlüssel"],["W01","Ich brauche den Schlüssel"]]:
		await fresh()
		var attempt := submit(row[1])
		frame_check(attempt,"RECOGNIZED","REQUEST_ITEM","player","key","positive","request")
		check(attempt.response.action == "give" and scene.response.text == "Hier, bitte.","Expected key transfer reply")
		if row[0] == "R10": check("AGREEMENT_MISMATCH" in attempt.parse.diagnostics,"Missing agreement diagnostic")
		await verify_world("player",false,true)
		var repeated := submit(row[1])
		check(repeated.response.action == "","Repeated transfer callback changed ownership")
		await verify_world("player",false,true)
		if row[0] == "R01":
			# First complete solution: close editor, aim and use the actual interaction ray.
			scene.close()
			check(not scene.player.is_movement_paused and not scene.panel.visible,"FPS control not restored")
			# Headless DisplayServer cannot capture an OS pointer; do not claim this UI check.
			if DisplayServer.get_name() != "headless": check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,"Mouse not captured")
			scene.player.position = Vector3(0,0.9,0.5)
			await physics_frame
			scene.player.camera.look_at(Vector3(0,1.2,-1))
			check(scene.ray_target() == "door","Player cannot target the door")
			scene.interact()
			scene.controls(true)
			await verify_world("player",true,true)
		record(row[0],row[1],attempt)
	# Information, problems and non-actionable phrases all start from a closed door/key at Anna.
	var rows := [
		["R03","Wo ist der Schlüssel?","RECOGNIZED","ASK_LOCATION","unresolved","key","positive","question","Ich habe den Schlüssel."],
		["R04","Ich habe keinen Schlüssel","RECOGNIZED","REPORT_PROBLEM","player","key","negative","statement","Soll ich dir helfen?"],
		["R05","Kannst du mir helfen?","RECOGNIZED","REQUEST_HELP","anna","","positive","request","Wobei?"],
		["R07","Warum ist die Tür zu?","RECOGNIZED","ASK_REASON","unresolved","door","positive","question","Das Zimmer ist privat."],
		["R08","Kann ich die Tür öffnen?","RECOGNIZED","ASK_PERMISSION","player","door","positive","question","Ja. Du kannst das Zimmer öffnen."],
		["R09","Schlüssel?","NEEDS_CLARIFICATION","","unresolved","key","positive","question","Meinst du den Ort, oder möchtest du den Schlüssel?"],
		["R11","Öffne die Tür nicht","RECOGNIZED","PROHIBIT_ACTION","anna","door","negative","prohibition","Okay. Ich mache das nicht."],
		["R12","Ich will nicht öffnen","RECOGNIZED","EXPRESS_DESIRE","player","","negative","statement","Okay. Du möchtest das nicht."],
		["R13","Anna hat keinen Schlüssel","RECOGNIZED","REPORT_STATE","anna","key","negative","statement","Verstanden."],
		["R14","Ich will nicht, dass Anna die Tür öffnet","UNSUPPORTED","","player","","negative","statement","Ich verstehe nicht."],
		["R15/unknown","Ich will Banane","UNKNOWN","","player","","unresolved","unresolved","Ich verstehe nicht."],
		["R15/reference","Das öffnen","NEEDS_CLARIFICATION","","unresolved","","positive","statement","Was möchtest du genau?"]
	]
	for row in rows:
		await fresh()
		var attempt := submit(row[1])
		frame_check(attempt,row[2],row[3],row[4],row[5],row[6],row[7])
		check(attempt.response.action == "" and scene.response.text == row[8],"Unexpected NPC reply/action")
		await verify_world("anna",false,row[0] == "R08")
		if row[0] == "R03": check(attempt.response.point == "key","Known information did not reference the key")
		if row[0] == "R04": check(scene.state.pending == "help_offer","Missing help offer")
		if row[0] == "R05": check(scene.state.pending == "help_target","Help target was guessed")
		if row[0] == "R09":
			check(scene.state.active and scene.state.pending == "key_intent","Clarification lost conversation context")
			var continuation := submit("Ich will Schlüssel")
			check(continuation.response.action == "give","Cannot continue after clarification")
			await verify_world("player",false,true)
		record(row[0],row[1],attempt)
	# Second complete solution: await the real actor's approach and check physical passage.
	for id in ["R06","W06"]:
		await fresh()
		var attempt := submit("Kannst du die Tür öffnen?")
		frame_check(attempt,"RECOGNIZED","REQUEST_ACTION","anna","door","positive","request")
		check(attempt.response.action == "open" and scene.action_running and not scene.state.opened,"NPC action did not start distinctly from opening")
		var initial_position: Vector3 = scene.anna.position
		await wait_for_action()
		check(scene.anna.position.distance_to(initial_position) > 0.5,"Anna did not approach the door")
		await verify_world("anna",true,true)
		var repeated := submit("Kannst du die Tür öffnen?")
		check(repeated.response.action == "" and not scene.action_running,"Repeated opening callback restarted action")
		await verify_world("anna",true,true)
		record(id,"Kannst du die Tür öffnen?",attempt)
	# W02/W03: exact same utterance; ownership/availability alone changes the result.
	for row in [["W02",{"key_location":"world"},"world","Ich kann dir den Schlüssel nicht geben."],["W03",{"available":false},"anna","Später, bitte."]]:
		await fresh(row[1])
		var attempt := submit("Ich brauche den Schlüssel")
		frame_check(attempt,"RECOGNIZED","REQUEST_ITEM","player","key","positive","request")
		check(attempt.response.action == "" and scene.response.text == row[3],"Missing contextual refusal")
		await verify_world(row[2],false,false)
		record(row[0],"Ich brauche den Schlüssel",attempt)
	# W04/W05: knowledge changes while the actual key location stays the same.
	for knows in [true,false]:
		await fresh({"key_location":"world","knows":knows})
		var attempt := submit("Wo ist der Schlüssel?")
		frame_check(attempt,"RECOGNIZED","ASK_LOCATION","unresolved","key","positive","question")
		check(attempt.response.action == "","Location question performed an action")
		check(attempt.response.point == ("key" if knows else ""),"Invented/omitted location reference")
		check(scene.response.text == ("Der Schlüssel ist dort." if knows else "Das weiß ich nicht."),"Location reply disagrees with knowledge")
		await verify_world("world",false,false)
		record("W04" if knows else "W05","Wo ist der Schlüssel?",attempt)
	for row in [["W07/no_access",{"anna_access":false}],["W07/busy",{"available":false}],["W07/no_key",{"key_location":"world"}],["W07/no_permission",{"may_grant":false}]]:
		await fresh(row[1])
		var attempt := submit("Kannst du die Tür öffnen?")
		frame_check(attempt,"RECOGNIZED","REQUEST_ACTION","anna","door","positive","request")
		check(attempt.response.action == "" and not scene.action_running,"Inaccessible/busy Anna opened the door")
		check(scene.response.text == ("Später, bitte." if row[0] == "W07/busy" else "Ich kann die Tür nicht öffnen."),"Missing explanation of refusal")
		await verify_world("world" if row[0] == "W07/no_key" else "anna",false,false)
		record(row[0],"Kannst du die Tür öffnen?",attempt)
	var file := FileAccess.open("user://language_parser_regression.json",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"cases":results,"failures":failures,
			"os_mouse_capture":{"status":"NOT_RUN" if DisplayServer.get_name() == "headless" else "CHECKED","reason":"Requires a graphical window"}},"\t"))
		file.close()
	print("LANGUAGE_PARSER_R_W_REGRESSION: %d cases, %d failures" % [results.size(),failures])
	if failures == 0: print("COMMUNICATION_SPEC_R01_R15_W01_W07_PASS")
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
