extends SceneTree
const Catalog = preload("res://game/characters/motifect_catalog.gd")
const Motifect = preload("res://game/characters/motifect_visual.gd")
const CanonicalMap = preload("res://game/characters/CharacterVisual.gd")

func _init() -> void:
	call_deferred("bake")

func bake() -> void:
	var source = load("res://addons/cogito/Assets/UniversalAnimationLibrary/AnimationLibrary_Godot_Standard.glb").instantiate()
	root.add_child(source)
	var src: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
	var player: AnimationPlayer = source.find_children("*","AnimationPlayer",true,false)[0]
	var driver = Catalog.SCENES.drink_from_cup.instantiate()
	root.add_child(driver)
	var dst: Skeleton3D = driver.find_children("*","Skeleton3D",true,false)[0]
	var helper = Motifect.new()
	for i in dst.get_bone_count(): dst.set_bone_name(i,helper._canonical(str(dst.get_bone_name(i))))
	var pairs := {}
	for native in CanonicalMap.BONE_MAP:
		var target := dst.find_bone(CanonicalMap.BONE_MAP[native])
		var origin := src.find_bone(native)
		if target >= 0 and origin >= 0: pairs[target] = origin
	var animation := Animation.new()
	animation.length = player.get_animation("Walk").length
	animation.loop_mode = Animation.LOOP_LINEAR
	var tracks := {}
	for i in pairs:
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track,NodePath("Skeleton3D:"+str(dst.get_bone_name(i))))
		tracks[i] = track
	var hip := dst.find_bone("J_Bip_C_Hips")
	var src_hip := src.find_bone("DEF-hips")
	var height_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(height_track,NodePath("Skeleton3D:J_Bip_C_Hips"))
	var idle = load("res://game/characters/calm_idle.tres")
	var neutral_height := 0.9994044
	for track in idle.get_track_count():
		if idle.track_get_type(track) == Animation.TYPE_POSITION_3D and idle.track_get_path(track).get_subname(0) == "J_Bip_C_Hips":
			neutral_height = idle.track_get_key_value(track,0).y
	player.play("Walk")
	var frames := int(ceil(animation.length*30))
	for frame in frames+1:
		var time := animation.length*frame/frames
		player.seek(time,true)
		for i in dst.get_bone_count():
			if not pairs.has(i): continue
			var origin: int = pairs[i]
			var delta := src.get_bone_global_pose(origin).basis * src.get_bone_global_rest(origin).basis.inverse()
			var final_basis := delta * dst.get_bone_global_rest(i).basis
			var parent := dst.get_bone_parent(i)
			var parent_basis := Basis.IDENTITY if parent < 0 else dst.get_bone_global_pose(parent).basis
			var rotation := (parent_basis.inverse()*final_basis).orthonormalized().get_rotation_quaternion()
			dst.set_bone_pose_rotation(i,rotation)
			animation.rotation_track_insert_key(tracks[i],time,rotation)
		var reference := src.get_bone_global_rest(src_hip).origin.y
		var dy := src.get_bone_global_pose(src_hip).origin.y-reference
		animation.position_track_insert_key(height_track,time,Vector3(0,neutral_height+dy*neutral_height/reference,0))
	assert(ResourceSaver.save(animation,"res://game/prologue/walk.tres") == OK)
	print("WALK_BAKED length=",animation.length," bones=",pairs.size())
	helper.free()
	source.free()
	driver.free()
	quit()
