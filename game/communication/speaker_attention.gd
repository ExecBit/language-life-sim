extends RefCounted
## Event-driven, short-lived attention. It never owns walking or pointing.
const MAX_DISTANCE := 6.0
const MIN_DISTANCE := 0.45
const MAX_VERTICAL_DISTANCE := 2.0
const FOLLOW_CONE := deg_to_rad(75.0)
const RETARGET_INTERVAL := 0.3
const ANGLE_DEADBAND := deg_to_rad(4.0)
var controller: Node3D
var remaining := 0.0
var retarget_in := 0.0
var owns_heading := false
var rest_heading := 0.0
var last_heading := 0.0
var initial_heading := 0.0

func actor():
	if not is_instance_valid(controller) or not is_instance_valid(controller.house): return null
	var actor_id := "lena"
	if controller.communication != null: actor_id = str(controller.communication.active_actor)
	return controller.house.actors.get(actor_id,controller.house.actors.get("lena"))

func begin_line(text: String) -> void:
	if text.strip_edges().is_empty(): return
	begin(clampf(2.0+text.length()*0.07,3.0,7.0))

func begin(seconds: float) -> void:
	stop()
	remaining = seconds
	retarget_in = 0.0
	tick(0.0)

func stop() -> void:
	var npc = actor()
	if is_instance_valid(npc) and owns_heading and not npc.walking and absf(angle_difference(npc.heading,last_heading)) < 0.001:
		npc.heading = rest_heading
	remaining = 0.0
	owns_heading = false

func target_visible(npc) -> bool:
	if not is_instance_valid(controller.player) or not is_instance_valid(controller.camera): return false
	var source: Vector3 = npc.global_position+Vector3(0,1.45,0)
	var target: Vector3 = controller.camera.global_position
	var offset := target-source
	var horizontal := Vector2(offset.x,offset.z).length()
	if horizontal < MIN_DISTANCE or offset.length() > MAX_DISTANCE or absf(offset.y) > MAX_VERTICAL_DISTANCE: return false
	var query := PhysicsRayQueryParameters3D.create(source,target)
	query.exclude = [npc.get_rid(),controller.player.get_rid()]
	return controller.house.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func tick(delta: float, suspended := false, selecting := false) -> void:
	if suspended: return # A pause/note freezes the same speech interval.
	if remaining <= 0: return
	remaining = maxf(0.0,remaining-delta)
	var npc = actor()
	if remaining <= 0 or not is_instance_valid(npc) or selecting:
		stop()
		return
	if npc.walking:
		stop() # Do not turn a walking body backwards or queue a look after arrival.
		return
	if controller.house.pointer_actor == "lena" and controller.house.pulse_time > 0 and npc.visual.current == "emote_point_at_opponent":
		stop() # The object indicated by the current gesture has priority.
		return
	if owns_heading and absf(angle_difference(npc.heading,last_heading)) > 0.001:
		owns_heading = false
		remaining = 0 # Another scripted action took ownership; never overwrite it.
		return
	retarget_in -= delta
	if retarget_in > 0: return
	retarget_in = RETARGET_INTERVAL
	if not target_visible(npc):
		stop() # Loss of visibility/proximity ends this glance, without reacquisition.
		return
	var offset: Vector3 = controller.player.global_position-npc.global_position
	var desired := atan2(-offset.x,-offset.z)
	if not owns_heading:
		rest_heading = npc.heading
		initial_heading = desired
		owns_heading = true
	elif absf(angle_difference(initial_heading,desired)) > FOLLOW_CONE:
		stop() # A player circling behind the NPC cannot induce a full-body chase.
		return
	if absf(angle_difference(npc.heading,desired)) >= ANGLE_DEADBAND:
		npc.face(controller.player.global_position)
	last_heading = npc.heading
