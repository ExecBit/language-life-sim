extends SceneTree
## Full route using FPS movement/collisions, ray-selected E and the normal composer.
## No direct item relocation, story index changes or player teleports in the driver.
var game: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("DORMITORY_ROUTE_FAIL: "+message)
		quit(1)
	return ok

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func walk(x: float, z: float) -> bool:
	var destination := Vector3(x,0,z)
	for frame in 900:
		var offset: Vector3 = destination-game.player.position
		offset.y = 0
		if offset.length() < 0.22:
			Input.action_release("forward")
			await create_timer(0.15).timeout
			return true
		game.player.body.rotation.y = atan2(-offset.x,-offset.z)
		game.player.head.rotation = Vector3.ZERO
		game.camera.rotation = Vector3.ZERO
		Input.action_press("forward")
		await physics_frame
	Input.action_release("forward")
	for i in game.player.get_slide_collision_count():
		var hit = game.player.get_slide_collision(i).get_collider()
		print("WALK_COLLIDER ",hit," target=",hit.get_meta("target_id","")," pos=",hit.global_position)
	return check(false,"Waypoint not reached: "+str(destination)+" at "+str(game.player.position))

func use(target: String) -> bool:
	game.camera.look_at(game.house.position_of(target))
	await physics_frame
	if not check(game._target() == target,"Expected ray target "+target+", got "+game._target()): return false
	game._interact()
	await process_frame
	return true

func run() -> void:
	var stage := Node.new()
	root.add_child(stage)
	current_scene = stage
	game = load("res://implementations/dormitory/game/prologue/prologue.tscn").instantiate()
	stage.add_child(game)
	await process_frame
	game._start_new()
	await physics_frame
	if not await use("bag"): return
	if not check(game.state.items.bag == "player","Bag pickup"): return
	if not await walk(0,2.2): return
	await wait_seconds(0.2)
	if not check(game.step.id == "b_water","Silent greeting must not block entry"): return
	game._skip_intro()
	if not await walk(0,0): return
	if not await walk(2.6,0): return
	await wait_seconds(4)
	game.camera.look_at(game.house.position_of("lena"))
	await wait_seconds(0.3)
	if not await walk(2.2,-3.55): return
	if not await use("bag_stand"): return
	await wait_seconds(6.0)
	if not check(game.state.items.bag == "bag_stand" and game.state.items.room_key == "key_tray","Room and animated key setdown: "+str(game.step.id)+" "+str(game.state.items)): return
	if not await walk(2.2,-1.3): return
	if not await walk(4.5,-1.3): return
	if not await use("room_key"): return
	if not check(game.state.items.room_key == "player","Key pickup"): return
	game.fixtures.open("player_pocket")
	game.fixtures.put_held()
	if not check(game.state.items.room_key == "player_pocket" and game.fixtures.inventory.inventory_slots[0] != null,"Cogito pocket UI owns one key"): return
	game.fixtures.close()
	if not await use("room_lamp"): return
	if not check(game.state.flags.get("lamp_on",false),"Lamp switch"): return
	if not await walk(2.2,-1.3): return
	if not await walk(2.6,0): return
	if not await use("room_door"): return
	await wait_seconds(0.8)
	if not check(not game.fixtures.room_door.is_open,"Cogito door closes through E"): return
	if not await use("room_door"): return
	await wait_seconds(0.8)
	if not check(game.fixtures.room_door.is_open,"Cogito door reopens through E"): return
	if not await walk(2.2,-3.9): return
	if not await use("drawer"): return
	if not check(game.fixtures.mode == "drawer_slot","Native container open"): return
	var help_key := InputEventKey.new()
	help_key.keycode = KEY_H
	help_key.pressed = true
	game._input_event(help_key)
	if not check(game.fixtures.mode == "" and game.communication.helper.visible and paused,"H from inventory opens the note without a second E handler"): return
	game.communication.toggle_helper()
	game.fixtures.open("player_pocket")
	game.fixtures._slot_clicked(game.fixtures.inventory,0,1)
	game.fixtures.close()
	if not await use("drawer"): return
	game.fixtures.put_held()
	if not check(game.state.items.room_key == "drawer_slot","Key storage"): return
	game.fixtures._slot_clicked(game.fixtures.inventory,0,1)
	game.fixtures.close()
	game.fixtures.open("player_pocket")
	game.fixtures.put_held()
	game.fixtures.close()
	print("DORMITORY_ROOM_OK")
	game._save()
	game._load_save()
	if not check(game.state.items.room_key == "player_pocket" and game.state.flags.get("lamp_on",false),"Save/load pocket and lamp"): return
	if not await walk(3.3,-4.2): return
	game._interact()
	await wait_seconds(0.2)
	if not check(game.state.day == 2,"Day one sleep"): return
	if not await walk(2.2,-4.0): return
	if not await walk(2.6,0): return
	if not await walk(0,0): return
	if not await walk(-2.7,0.0): return
	await wait_seconds(12)
	if not await use("anna"): return
	game.communication.submit("Hallo!")
	if not check(game.communication.active_actor == "anna","Anna greeting context"): return
	var before_location: Dictionary = game.state.items.duplicate()
	game.communication.submit("Wo ist das Wasser?")
	if not check(game.house.pointer_actor == "anna" and game.house.pointer_target == "bottle" and game.state.items == before_location,"Anna points at real water"): return
	game.communication.submit("Danke!")
	if not check(game.ui.speaker.text.begins_with("Анна"),"Thanks stays with Anna"): return
	game.communication.close()
	await wait_seconds(6)
	if not await walk(-2.7,-0.3): return
	if not await use("anna"): return
	game.communication.submit("Wasser, bitte")
	game.communication.submit("Wasser, bitte") # repeat during handoff must not create a second cup
	game._save()
	game._load_save()
	await wait_seconds(1.5)
	if not check(game.state.items.cup == "player","Normal cup handoff: "+str(game.state.items)+" reply="+game.ui.line.text+" npc="+str(game.house.actors.anna.position)): return
	game.communication.close()
	if not await walk(-4.9,-1.35): return
	if not await use("bottle"): return
	await wait_seconds(0.2)
	game._set_pause(true)
	await wait_seconds(1.0)
	if not check(not game.state.flags.get("water_drunk",false),"Pause freezes drinking action"): return
	game._set_pause(false)
	await wait_seconds(1.7)
	if not check(game.state.flags.get("water_drunk",false),"Visible drink completed"): return
	# Decline breakfast normally, then leave it to Lena and return to bed.
	if not await use("lena"): return
	game.communication.submit("Nein.")
	await wait_seconds(12)
	if game.communication.conversation_open: game.communication.close()
	if not await walk(-2.6,0.0): return
	if not await walk(0,0): return
	# All rooms are real, reachable interiors behind ordinary-width doors.
	for room_id in ["common","spare","anna","lena"]:
		var room: Dictionary = game.house.Layout.ROOMS[room_id]
		if not await walk(0,room.door_z): return
		if not game.house.doors[room_id].is_open:
			if not await use("door_"+room_id): return
			await wait_seconds(0.8)
		if not await walk(room.side*3.0,room.door_z): return
		if not check(game.house.Layout.room_at(game.player.position) == room_id,"Entered "+room_id): return
		if not await walk(0,room.door_z): return
	if not await walk(0,-10.8): return
	if not game.house.doors.bathroom.is_open:
		if not await use("door_bathroom"): return
		await wait_seconds(0.8)
	if not await walk(0,-13.2): return
	if not check(game.house.Layout.room_at(game.player.position) == "bathroom","Entered shared bathroom"): return
	if not await walk(0,-10.8): return
	print("DORMITORY_ROOMS_VISITED_OK: bathroom, common, spare, Anna, Lena, kitchen, player bedroom")
	if not await walk(0,0): return
	if not await walk(2.6,0): return
	if not await walk(2.2,-4.0): return
	if not await walk(3.3,-4.2): return
	game._interact()
	if not check(game.state.finished and game.state.held("player") == "" and game.state.items.room_key == "player_pocket" and game.state.flags.breakfast_result == "declined","Day two safe sleep, breakfast outcome and pocket persistence"): return
	game._save()
	game._load_save()
	if not check(game.state.finished and game.state.flags.get("day2_sleep",false),"Finished checkpoint reload"): return
	print("DORMITORY_PHYSICS_ROUTE_OK: silent greeting, skip water, door, bag, generated key, Cogito inventory/container/lamp, save/load, Anna, water, drink, decline, sleep")
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
