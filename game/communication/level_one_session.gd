extends Node
## Adapter to the existing level-one events. No experiment room state or shop logic.
const Parser = preload("res://game/communication/parser.gd")
const Catalog = preload("res://game/communication/word_catalog.gd")
const Composer = preload("res://game/communication/word_composer.gd")
const Helper = preload("res://game/communication/helper_catalog.gd")
const Attention = preload("res://game/communication/speaker_attention.gd")
var attention = Attention.new()
const Residents = preload("res://game/prologue/residents.gd")
const OBJECTS = Residents.OBJECTS
const SEMANTICS = Residents.SEMANTICS
const IDENTIFY = Residents.IDENTIFY

var controller: Node3D
var composer: VBoxContainer
var helper: PanelContainer
var helper_grid: GridContainer
var helper_button: Button
var selecting := false
var context := {"speaker":"lena","addressee":"lena","last_utterance":"","pending":"","pointed_target_id":"","step_id":""}
var pending_text := ""
var closed_step := ""
var paused := false
var saved_focus: Control
var saved_caret := 0
var helper_tree_paused := false
var last_parse := {}
var seen_step := ""
var conversation_open := false
var subtitle_panel: PanelContainer
var subtitle: Label
var subtitle_time := 0.0
var held_tween: Tween
var held_heading := 0.0
var active_actor := "lena"
var external_line := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	attention.controller = controller
	composer = Composer.new()
	controller.ui.dialog.get_child(0).add_child(composer)
	composer.help_button.text = "H — слова"
	composer.submitted.connect(submit)
	composer.cancelled.connect(close)
	composer.help_requested.connect(toggle_helper)
	composer.point_requested.connect(begin_point)
	composer.focus_changed.connect(func(): if is_instance_valid(controller): controller._controls())
	composer.hide()
	subtitle_panel = controller.ui.panel()
	subtitle_panel.anchor_left = 0.22
	subtitle_panel.anchor_right = 0.78
	subtitle_panel.anchor_top = 1.0
	subtitle_panel.anchor_bottom = 1.0
	subtitle_panel.offset_top = -155
	subtitle_panel.offset_bottom = -85
	controller.ui.root.add_child(subtitle_panel)
	subtitle = controller.ui.label("",24)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_panel.add_child(subtitle)
	subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_panel.hide()
	helper_button = Button.new()
	helper_button.text = "H — слова"
	helper_button.position = Vector2(24,48)
	helper_button.pressed.connect(toggle_helper)
	controller.ui.root.add_child(helper_button)
	helper = controller.ui.centered(Vector2(620,520))
	var column := VBoxContainer.new()
	helper.add_child(column)
	column.add_child(controller.ui.label("СЛОВА · заметка",24))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(570,410)
	column.add_child(scroll)
	helper_grid = GridContainer.new()
	helper_grid.columns = 2
	helper_grid.add_theme_constant_override("h_separation",28)
	scroll.add_child(helper_grid)
	composer.add_button(column,"Закрыть · Esc",toggle_helper)
	helper.hide()

func enabled() -> bool:
	return not controller.start_in_shop and not controller.shopping.active()

func blocks_movement() -> bool:
	return enabled() and (helper.visible or (conversation_open and not selecting))

func sync_actor() -> void:
	var actor = controller.house.actors.get(active_actor,controller.house.actors.lena)
	if is_instance_valid(held_tween) and (actor.moving != held_tween or not held_tween.is_valid()): held_tween = null
	if enabled() and conversation_open:
		if is_instance_valid(actor.moving) and actor.moving.is_running() and not is_instance_valid(held_tween):
			held_tween = actor.moving
			held_heading = actor.heading
			held_tween.pause()
			actor.walking = false
			actor.visual.stop()
	elif is_instance_valid(held_tween):
		if actor.moving == held_tween:
			actor.heading = held_heading
			actor.walking = true
			actor.visual.play("walking",true)
			held_tween.play()
		held_tween = null

func reset() -> void:
	composer.opener_key = 0
	attention.stop()
	conversation_open = false
	active_actor = "lena"
	external_line = ""
	sync_actor()
	subtitle_time = 0.0
	subtitle_panel.hide()
	if helper.visible: toggle_helper()
	composer.clear()
	composer.release()
	composer.hide()
	selecting = false
	pending_text = ""
	closed_step = ""
	seen_step = ""
	context = {"speaker":"lena","addressee":"lena","last_utterance":"","pending":"","pointed_target_id":"","step_id":""}

func suspend() -> void:
	attention.stop()
	conversation_open = false
	sync_actor()
	subtitle_panel.hide()
	if helper.visible: toggle_helper()
	composer.release()
	composer.hide()
	helper_button.hide()

func _process(delta: float) -> void:
	sync_mode()
	if not enabled(): return
	sync_actor()
	attention.tick(delta,controller.paused or helper.visible or controller.menu_active,selecting)
	controller.ui.answers.hide()
	helper_button.visible = controller.initialized and not controller.menu_active and not controller.paused
	if helper.visible: controller.ui.dialog.hide()
	if not controller.paused and not helper.visible and not controller.menu_active:
		subtitle_time = maxf(0.0,subtitle_time-delta)
	subtitle_panel.visible = subtitle_time > 0 and not conversation_open and not helper.visible and not controller.paused and not controller.menu_active

func show_subtitle(text: String, speaker := "Лена") -> void:
	if text.strip_edges().is_empty(): return
	if speaker == "Лена": attention.begin_line(text)
	subtitle.text = speaker+": "+text
	subtitle_time = clampf(2.0+text.length()*0.07,3.0,7.0)
	subtitle_panel.visible = not conversation_open and not helper.visible and not controller.paused and not controller.menu_active
	controller.ui.dialog.hide()

func sync_mode() -> void:
	if not enabled():
		attention.stop()
		conversation_open = false
		sync_actor()
		subtitle_panel.hide()
		composer.release()
		composer.hide()
		helper_button.hide()
		if helper.visible: controller.get_tree().paused = helper_tree_paused
		helper.hide()
		controller.ui.answers.show()
		controller.ui.dialog.offset_top = -195

func meet(text: String, target := "") -> void:
	var regex := RegEx.new()
	regex.compile("[\\p{L}]+")
	for token in regex.search_all(text):
		for entry in Catalog.lookup(token.get_string()):
			if Helper.NEW.has(entry.semantic_id): controller.state.flags["comm_seen_"+entry.semantic_id] = true
	if SEMANTICS.has(target) and Helper.NEW.has(SEMANTICS[target]): controller.state.flags["comm_seen_"+SEMANTICS[target]] = true

func display() -> void:
	if not enabled(): return
	# Existing saves already contain exposure events; do not reveal later content.
	for entry in controller.state.entered:
		for unit in {"b_water":["water","cup"],"c_bag":["bag"],"c_key":["key"],"f_offer":["bread"],"f_take":["bread"]}.get(entry,[]):
			controller.state.flags["comm_seen_"+unit] = true
	controller.ui.answers.hide()
	controller.ui.answer_ids.clear()
	controller.ui.dialog.offset_top = -355
	if not external_line.is_empty(): controller.ui.speaker.text = ("Анна" if active_actor == "anna" else "Лена")+" → Вы"
	var step_id: String = "external:"+active_actor if not external_line.is_empty() else controller.step.id
	var changed: bool = context.step_id != step_id
	if changed:
		composer.clear()
		composer.release()
		closed_step = ""
		context.pointed_target_id = ""
	context.step_id = step_id
	var line_text: String = external_line if not external_line.is_empty() else controller._line()
	var new_line: bool = changed or context.get("script_line","") != line_text
	if new_line:
		context.last_utterance = line_text
		context.script_line = line_text
	else: controller.ui.line.text = context.last_utterance
	if new_line: controller.ui.line.text = line_text
	if changed: context.pending = "offer" if step_id in ["b_water","f_offer"] else ""
	meet(line_text,str(controller.step.get("point","")))
	composer.visible = conversation_open and not selecting and not paused and not helper.visible
	controller.ui.dialog.visible = composer.visible
	if new_line and not conversation_open: show_subtitle(line_text,"Анна" if active_actor == "anna" else "Лена")
	elif new_line: attention.begin_line(line_text)
	sync_actor()

func reopen() -> void:
	if not enabled(): return
	active_actor = str(controller.step.get("speaker","lena"))
	external_line = ""
	context.addressee = active_actor
	context.speaker = active_actor
	conversation_open = true
	controller.talking = true
	subtitle_panel.hide()
	closed_step = ""
	controller._show_dialog()
	controller.ui.dialog.show()
	composer.show()
	composer.prefix.grab_focus()
	sync_actor()
	controller._controls()
	attention.begin(2.0)

func open_for(actor_id: String, line_text: String) -> void:
	if not enabled() or not controller.house.actors.has(actor_id): return
	active_actor = actor_id
	external_line = line_text
	context.addressee = actor_id
	context.speaker = actor_id
	conversation_open = true
	controller.talking = true
	subtitle_panel.hide()
	closed_step = ""
	controller._show_dialog()
	controller.ui.dialog.show()
	composer.show()
	composer.prefix.grab_focus()
	controller.house.actors[actor_id].face(controller.player.global_position)
	controller.house.actors[actor_id].attention.show()
	controller._controls()
	attention.begin(2.0)

func before_transition(keep_open := false) -> void:
	if not enabled(): return
	if keep_open: return
	attention.stop()
	conversation_open = false
	sync_actor()
	composer.clear()
	composer.release()
	composer.hide()
	context.pending = ""
	active_actor = "lena"
	external_line = ""

func pause(value: bool) -> void:
	if not enabled(): return
	paused = value
	if value:
		saved_focus = controller.get_viewport().gui_get_focus_owner()
		if saved_focus is LineEdit: saved_caret = saved_focus.caret_column
		composer.hide()
	else:
		composer.visible = conversation_open and not selecting
		restore_focus.call_deferred()

func restore_focus() -> void:
	if paused or helper.visible: return
	if is_instance_valid(saved_focus) and saved_focus.is_visible_in_tree():
		saved_focus.grab_focus()
		if saved_focus is LineEdit: saved_focus.caret_column = saved_caret

func input(event: InputEvent) -> bool:
	if not enabled(): return false
	if composer.consume_opener(event): return true
	if controller.menu_active: return false
	if helper.visible:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE,KEY_H]:
			toggle_helper()
			controller.get_viewport().set_input_as_handled()
		return true
	if controller.paused: return false
	if composer.route_key(event): return true
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE: return false
		if composer.editing(): return true # GUI still receives letters, including h.
		if event.keycode == KEY_H:
			toggle_helper()
			controller.get_viewport().set_input_as_handled()
			return true
	return false

func toggle_helper() -> void:
	if not enabled(): return
	if helper.visible:
		helper.hide()
		controller.get_tree().paused = helper_tree_paused
		controller._show_dialog()
		if is_instance_valid(saved_focus) and saved_focus.is_visible_in_tree():
			saved_focus.grab_focus()
			if saved_focus is LineEdit: saved_focus.caret_column = saved_caret
	else:
		saved_focus = controller.get_viewport().gui_get_focus_owner()
		if saved_focus is LineEdit: saved_caret = saved_focus.caret_column
		for child in helper_grid.get_children():
			helper_grid.remove_child(child)
			child.queue_free()
		for row in Helper.rows(controller.state.flags):
			helper_grid.add_child(controller.ui.label(row[1],19))
			helper_grid.add_child(controller.ui.label(row[2],19))
		var key: String = str(context.get("step_id",controller.step.get("id","start")))+":helper"
		controller.state.help[key] = int(controller.state.help.get(key,0))+1
		composer.release()
		helper_tree_paused = controller.get_tree().paused
		helper.show()
		controller.ui.dialog.hide()
		controller.get_tree().paused = true
		controller._save()
	controller._controls()

func close() -> void:
	attention.stop()
	conversation_open = false
	sync_actor()
	composer.release()
	composer.hide()
	closed_step = str(controller.step.id)
	controller.ui.dialog.hide()
	controller.pointer = false
	controller.talking = false
	if controller.house.actors.has(active_actor): controller.house.actors[active_actor].attention.hide()
	active_actor = "lena"
	external_line = ""
	context.addressee = "lena"
	context.speaker = "lena"
	controller._controls()

func begin_point() -> void:
	if not enabled() or not conversation_open: return
	attention.stop()
	pending_text = composer.phrase.text
	selecting = true
	controller.selecting = true
	composer.release()
	composer.hide()
	controller.ui.dialog.hide()
	controller.pointer = false
	controller._controls()

func cancel_point() -> void:
	selecting = false
	controller.selecting = false
	composer.phrase.text = pending_text
	pending_text = ""
	controller._show_dialog()
	composer.prefix.grab_focus()
	controller._controls()
	attention.begin(2.0)

func confirm_point(target: String) -> void:
	if target == "" or (not controller.house.items.has(target) and not controller.house.anchors.has(target) and not SEMANTICS.has(target)): return
	if controller.state.items.get(target,"") in ["player","lena"]: return
	context.pointed_target_id = target
	selecting = false
	controller.selecting = false
	var text := pending_text
	pending_text = ""
	controller._show_dialog()
	composer.phrase.text = text
	composer.prefix.grab_focus()
	controller._controls()
	if not text.strip_edges().is_empty(): submit(text)

func reply(text: String) -> void:
	if conversation_open: attention.begin_line(text)
	controller.ui.speaker.text = ("Анна" if active_actor == "anna" else "Лена")+" → Вы"
	controller.ui.line.text = text
	context.last_utterance = text
	meet(text)
	controller.ui.dialog.visible = conversation_open and not selecting
	composer.visible = conversation_open and not selecting
	if not conversation_open: show_subtitle(text)

func submit(text: String) -> void:
	if not enabled() or not conversation_open or helper.visible or controller.menu_active or controller.paused or controller.transition > 0 or text.strip_edges().is_empty(): return
	if not controller.house.actors.has(active_actor) or controller.player.position.distance_to(controller.house.actors[active_actor].position) > 4.5:
		reply("Komm bitte näher.")
		return
	var parse_context := {"active":true,"pending":context.pending,"addressee":active_actor,
		"offer_pending":active_actor == "lena" and controller.step.id in ["b_water","f_offer"] and controller.step.id not in controller.state.completed,
		"pointed_object_id":SEMANTICS.get(context.pointed_target_id,context.pointed_target_id)}
	var parsed := Parser.parse(text,context.pointed_target_id,parse_context)
	last_parse = parsed.duplicate(true)
	if parsed.status == "NEEDS_CLARIFICATION" and parsed.frame.question_type == "what" and parsed.frame.object_id == "":
		begin_point()
		return
	var before: Dictionary = controller.state.items.duplicate()
	if parsed.status != "RECOGNIZED": reply("Was meinst du genau?" if parsed.status == "NEEDS_CLARIFICATION" else "Ich verstehe nicht.")
	else: resolve(parsed)
	var history: Variant = JSON.parse_string(str(controller.state.flags.get("comm_history","[]")))
	if not history is Array: history = []
	history.append({"step":context.step_id,"intent":parsed.intent,"status":parsed.status,"frame":parsed.frame,
		"assisted":int(controller.state.help.get(context.step_id+":helper",0)) > 0,"items_changed":before != controller.state.items})
	if history.size() > 100: history.pop_front()
	controller.state.flags.comm_history = JSON.stringify(history)
	composer.clear()
	controller._save()

func resolve(parsed: Dictionary) -> void:
	if parsed.get("status","") != "RECOGNIZED": return
	var frame: Dictionary = parsed.frame
	var intent: String = parsed.intent
	var id: String = controller.step.id
	if intent == "GREETING":
		if active_actor == "anna":
			controller.house.actors.anna.gesture("wave_hello")
			reply("Hallo!")
		elif id == "a_greeting": controller._answer("hello")
		else: reply("Hallo!")
	elif intent in ["ACCEPT","REFUSE"]:
		if active_actor != "lena" or id not in ["b_water","f_offer"] or id in controller.state.completed: reply("Was meinst du?")
		else:
			var previous_index: int = controller.state.index
			controller._answer("yes" if intent == "ACCEPT" else "no")
			if controller.state.index != previous_index:
				controller.house.actors[active_actor].gesture("nod_yes" if intent == "ACCEPT" else "shake_head_no")
	elif intent == "THANKS":
		if active_actor == "lena" and controller._free_conversation(): controller._answer("thanks")
		else: reply("Gern.")
	elif intent == "FAREWELL":
		if active_actor == "lena" and controller._free_conversation(): controller._answer("bye")
		else: reply("Tschüss!")
	elif intent == "POLITENESS":
		if active_actor == "lena" and id == "f_place": controller._answer("morning_welcome")
		else: reply("Gern.")
	elif intent == "APOLOGY": reply("Ja?")
	elif intent == "REQUEST_REPEAT":
		controller.state.ask_help(id,"repeat")
		reply(context.last_utterance)
	elif intent == "REPORT_NONUNDERSTANDING":
		controller.state.ask_help(id,"show")
		var target: String = controller.step.get("point",controller.last_target) if active_actor == "lena" and external_line == "" else ("bottle" if "Wasser" in context.last_utterance else active_actor)
		if target != "": controller.house.point(active_actor,target)
		reply("Anna." if target == "anna" else "Hier.")
	elif intent == "IDENTIFY":
		var target: String = context.pointed_target_id
		if target == "": target = OBJECTS.get(frame.object_id,"")
		if not IDENTIFY.has(target) or target not in Residents.PEOPLE[active_actor].known: reply("Das weiß ich nicht.")
		else:
			controller.house.point(active_actor,target)
			meet("",target)
			reply(IDENTIFY[target])
	elif intent == "REQUEST_ITEM" and frame.object_id in ["water","cup"]:
		reply(controller.life.offer_water(active_actor))
	elif intent in ["ASK_LOCATION","REQUEST_ITEM"]:
		var target: String = OBJECTS.get(frame.object_id,"")
		if target not in Residents.PEOPLE[active_actor].known: reply("Das weiß ich nicht.")
		elif controller.state.items.get(target,"") in ["player","player_pocket"]: reply("Du hast das.")
		else:
			controller.house.point(active_actor,target)
			meet("",target)
			reply("Dort.")
	elif intent == "REQUEST_HELP":
		context.pending = "help_target"
		if frame.object_id == "": reply("Wobei?")
		else:
			var target: String = OBJECTS.get(frame.object_id,controller.step.get("point","") if active_actor == "lena" else "")
			if target in Residents.PEOPLE[active_actor].known:
				controller.house.point(active_actor,target)
				reply("Hier.")
			else: reply("Das weiß ich nicht.")
			context.pending = "offer" if id in ["b_water","f_offer"] else ""
	elif intent == "PROHIBIT_ACTION" or (intent == "EXPRESS_DESIRE" and frame.polarity == "negative"): reply("Okay.")
	else: reply("Was möchtest du genau?")
