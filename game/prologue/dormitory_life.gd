extends Node
const Residents = preload("res://game/prologue/residents.gd")
## Small authored routines; world transfers remain explicit and recoverable.
var controller: Node3D
var key_time := 0.0
var key_started := false
var anna_wait := 0.0
var anna_route := false
var was_talking := false
var resume_work := false
var handoff_time := 0.0
var drink_tween: Tween

func reset() -> void:
	key_time = 0
	key_started = false
	anna_wait = 0
	anna_route = false
	was_talking = false
	resume_work = false
	stop_drink()

func stop_drink() -> void:
	if is_instance_valid(drink_tween): drink_tween.kill()
	controller.held.position = Vector3(0.34,-0.29,-0.68)
	controller.held.rotation = Vector3.ZERO

func enter_step() -> void:
	if controller.step.get("wait","") == "npc_place": controller.house.actors.lena.gesture("put_down_object_table")
	if controller.step.id == "c_follow":
		controller.fixtures.room_door.open_door(controller.player.player_interaction_component)
		controller.house.actors.lena.gesture("a01_room_invitation")
	if controller.step.id != "c_key":
		key_started = false
		key_time = 0
	var anna = controller.house.actors.anna
	if controller.state.day == 1:
		anna_route = false
		anna.go(Vector3(0,0,-4.7),true)
	elif not anna_route:
		anna.go(Vector3(-2.3,0,-1.6) if controller.state.flags.get("anna_introduced",false) else Vector3(0,0,-4.7),true)
		if not controller.state.flags.get("anna_introduced",false): anna.go(Vector3(-2.2,0,0.4))
		anna_route = true

func tick(delta: float) -> void:
	if controller.start_in_shop or controller.state.finished: return
	var state = controller.state
	var lena = controller.house.actors.lena
	var comm = controller.communication
	if controller.step.id == "c_key" and state.items.room_key == "lena" and not lena.walking:
		if not key_started:
			key_started = true
			lena.gesture("a01_key_setdown")
		key_time += delta
		if key_time >= 1.6:
			for surface in ["key_tray","surface_room","nightstand","bedside_spare"]:
				if surface not in state.items.values():
					state.transfer("room_key","lena",surface)
					controller.house.sync_items(state,controller.held)
					controller._save()
					break
	if state.flags.has("water_handoff_source"):
		handoff_time -= delta
		if handoff_time <= 0:
			var holder: String = state.items.cup
			if holder in ["lena","anna"] and state.held("player") == "" and controller.player.position.distance_to(controller.house.actors[holder].position) < 3.5:
				if state.transfer("cup",holder,"player"):
					state.flags.water_requested = true
					state.flags.erase("water_handoff_source")
			else: settle_handoff()
			controller.house.sync_items(state,controller.held)
			controller._save()
	if state.day != 2: return
	var anna = controller.house.actors.anna
	if not state.flags.get("anna_introduced",false) and not anna.walking and not comm.conversation_open and controller._visible_actor("anna") and controller.player.position.distance_to(anna.position) < 4:
		comm.show_subtitle(anna_greeting(),"Анна")
	if anna_wait > 0 and not comm.conversation_open:
		anna_wait -= delta
		if anna_wait <= 0: anna.go(Vector3(-2.3,0,-1.6))
	_tick_breakfast_motion()

func _tick_breakfast_motion() -> void:
	var lena = controller.house.actors.lena
	var comm = controller.communication
	var talking: bool = comm.conversation_open and comm.active_actor == "lena"
	if was_talking and not talking: resume_work = true
	var began_talking: bool = talking and not was_talking
	was_talking = talking
	if lena.walking or controller.state.cooking.get("activity","") == "finished" or controller.step.get("wait","") == "npc_place": return
	if talking:
		if began_talking: lena.gesture("a02_breakfast_attention")
		return
	# Explicit pointing and item handoffs finish before returning to the counter.
	if controller.house.pointer_actor == "lena" and controller.house.pulse_time > 0 and lena.visual.current == "emote_point_at_opponent": return
	if controller.state.held("lena") != "": return
	if comm.active_actor == "lena": comm.attention.stop()
	lena.face(controller.house.zones.breakfast_work)
	# Turn the body first: a working clip must not start facing the player/shelf.
	if absf(angle_difference(lena.rotation.y,lena.heading)) > 0.12:
		if lena.visual.current in ["a02_breakfast_routine","a02_breakfast_resume","a02_breakfast_attention"]: lena.visual.stop()
		return
	if resume_work:
		resume_work = false
		lena.gesture("a02_breakfast_resume")
	elif lena.visual.current in ["standing","a02_breakfast_attention"]:
		lena.visual.play("a02_breakfast_routine",true)

func anna_greeting() -> String:
	if controller.state.flags.get("anna_introduced",false): return "Hallo!"
	controller.state.flags.anna_introduced = true
	var anna = controller.house.actors.anna
	anna.face(controller.player.global_position)
	anna.gesture("wave_hello")
	anna_wait = 3.0
	controller._save()
	return Residents.PEOPLE.anna.greeting

func offer_water(actor_id: String) -> String:
	var state = controller.state
	if state.items.cup == "player": return "Du hast die Tasse."
	if state.held("player") != "": return "Stell das bitte zuerst ab."
	var npc = controller.house.actors[actor_id]
	if state.items.cup in ["lena","anna","player_pocket"]: return "Einen Moment, bitte."
	if npc.position.distance_to(controller.house.position_of("cup")) > 2.5 or controller.player.position.distance_to(npc.position) > 3.2:
		controller.house.point(actor_id,"cup")
		return "Die Tasse ist dort."
	var source: String = state.items.cup
	if not state.transfer("cup",source,actor_id): return "Einen Moment, bitte."
	state.flags.water_handoff_source = source
	handoff_time = 1.2
	npc.gesture("pick_up_object_table")
	controller.house.sync_items(state,controller.held)
	controller._save()
	return "Bitte."

func settle_handoff() -> void:
	var state = controller.state
	if not state.flags.has("water_handoff_source"): return
	if state.items.cup in ["lena","anna"]:
		var source: String = str(state.flags.water_handoff_source)
		for destination in [source,"tray","bedside_spare","surface_common","surface_side"]:
			if destination not in state.items.values():
				if state.transfer("cup",str(state.items.cup),destination): state.flags.erase("water_handoff_source")
				break
	else: state.flags.erase("water_handoff_source")

func drink() -> void:
	if is_instance_valid(drink_tween) and drink_tween.is_running(): return
	var hand = controller.held
	drink_tween = create_tween()
	drink_tween.tween_property(hand,"position",Vector3(0,-0.05,-0.26),0.4)
	drink_tween.parallel().tween_property(hand,"rotation:x",0.6,0.4)
	drink_tween.tween_interval(0.7)
	drink_tween.tween_property(hand,"position",Vector3(0.34,-0.29,-0.68),0.4)
	drink_tween.parallel().tween_property(hand,"rotation:x",0.0,0.4)
	drink_tween.tween_callback(func():
		controller.state.flags.water_drunk = true
		controller.ui.notify("Вы выпили воды.")
		controller._save()
	)
