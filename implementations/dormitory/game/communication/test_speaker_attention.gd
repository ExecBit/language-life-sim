extends SceneTree
var scene
var session
var npc
var attention
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fixture(player_position := Vector3(0,0.9,2)) -> void:
	attention.stop()
	session.conversation_open = false
	session.sync_actor()
	scene.house.pulse_time = 0
	npc.go(Vector3.ZERO,true)
	npc.heading = 0
	npc.rotation.y = 0
	scene.player.position = player_position
	scene.player.body.rotation = Vector3.ZERO
	scene.player.head.rotation = Vector3.ZERO
	scene.player.head.position.y = 0
	scene.player.eyes.position = Vector3.ZERO
	scene.camera.rotation = Vector3.ZERO
	scene.player.set_physics_process(false)
	await physics_frame
	await physics_frame

func run() -> void:
	scene = load("res://implementations/dormitory/game/prologue/prologue.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	scene._start_new()
	session = scene.communication
	session.set_process(false) # Advance attention deterministically; actor smoothing still runs.
	npc = scene.house.actors.lena
	attention = session.attention
	await fixture()
	check(attention.target_visible(npc),"Nearby player is visible")
	attention.begin_line("Hallo!")
	check(attention.owns_heading and absf(angle_difference(npc.heading,PI)) < 0.001,"Speech turns body toward addressed player, including behind")
	check(npc.rotation.y == 0,"Speech does not snap the visible model")
	await create_timer(0.15).timeout
	check(absf(npc.rotation.y) > 0.1 and absf(npc.rotation.y) < 1.2,"Body rotates smoothly")
	await create_timer(1.0).timeout
	check(absf(angle_difference(npc.rotation.y,PI)) < 0.1,"Visible model reaches speaking direction")
	attention.tick(3.1)
	check(attention.remaining == 0 and not attention.owns_heading and npc.heading == 0,"Speech expiry restores previous idle/task direction")
	scene.player.position.x = 2
	attention.tick(10)
	check(npc.heading == 0 and npc.pending_face == Vector3.INF,"Idle never keeps tracking or queues a later look")
	await fixture()
	attention.begin(2)
	attention.tick(5,true)
	check(attention.remaining == 2,"Pause freezes attention interval")
	attention.tick(2.1)
	check(attention.remaining == 0,"Attention still expires after pause")
	await fixture()
	attention.begin(3)
	scene.player.position.x = 0.03
	var heading: float = npc.heading
	attention.tick(0.31)
	check(npc.heading == heading,"Small target motion has a deadband")
	scene.player.position.x = 0.5
	attention.tick(0.31)
	check(absf(angle_difference(npc.heading,heading)) > 0.1,"Speech follows modest player movement")
	scene.player.position = Vector3(2,0.9,0)
	attention.tick(0.31)
	check(attention.remaining == 0 and npc.heading == 0,"Player circling behind ends glance instead of spinning NPC")
	for position in [Vector3(0,0.9,8),Vector3(0.01,0.9,0.01),Vector3(0,5,2)]:
		await fixture(position)
		attention.begin_line("Hallo!")
		check(not attention.owns_heading and npc.heading == 0,"No unsafe distant/coincident/vertical gaze: "+str(position))
	await fixture()
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1,2,0.2)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(0,1.5,1)
	scene.add_child(wall)
	await physics_frame
	await physics_frame
	attention.begin_line("Hallo!")
	check(not attention.owns_heading and npc.heading == 0,"Does not look through opaque obstacles")
	wall.queue_free()
	await physics_frame
	await physics_frame
	attention.tick(1)
	check(npc.heading == 0,"Returning visibility does not reacquire an expired glance")
	await fixture()
	attention.begin(3)
	scene.player.position.z = 8
	attention.tick(0.31)
	check(attention.remaining == 0 and npc.heading == 0,"Leaving hearing distance releases attention")
	await fixture()
	npc.go(Vector3(1,0,0))
	attention.begin_line("Komm!")
	check(attention.remaining == 0 and npc.pending_face == Vector3.INF,"Walking never queues a backwards face after arrival")
	await fixture()
	scene.house.point("lena","bag_stand")
	heading = npc.heading
	attention.begin_line("Hier.")
	check(npc.heading == heading and not attention.owns_heading,"Pointing keeps attention on the indicated object")
	await fixture()
	attention.begin(3)
	npc.face(Vector3(2,0,0))
	heading = npc.heading
	attention.tick(0.31)
	check(npc.heading == heading and attention.remaining == 0,"Another scripted direction takes priority without stale restoration")
	await fixture()
	session.show_subtitle("Hallo!")
	check(attention.owns_heading,"Automatic NPC subtitle starts a bounded glance")
	attention.stop()
	session.show_subtitle("Ja.","Вы")
	check(attention.remaining == 0,"Player subtitle cannot start NPC speech attention")
	session.reopen()
	check(attention.owns_heading and attention.remaining == 2,"E conversation starts a brief listening glance")
	attention.tick(2.1)
	check(session.conversation_open and attention.remaining == 0,"Open composer does not mean perpetual eye contact")
	session.reply("Hallo!")
	check(attention.owns_heading,"Actual NPC reply renews speech attention")
	session.begin_point()
	check(attention.remaining == 0,"Player target selection stops player tracking")
	session.cancel_point()
	check(attention.remaining > 0,"Returning to conversation allows a short listening glance")
	session.close()
	check(attention.remaining == 0,"Closing conversation releases attention immediately")
	await fixture()
	attention.begin(3)
	scene.start_in_shop = true
	session.sync_mode()
	check(attention.remaining == 0,"Legacy level switch releases attention")
	scene.queue_free()
	await process_frame
	attention.remaining = 2
	attention.tick(0.3)
	check(attention.remaining == 0,"Freed actor/controller is safe")
	print("SPEAKER_ATTENTION: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("MVP_BOUNDED_SPEAKER_ATTENTION_PASS")
	quit(1 if failures else 0)
