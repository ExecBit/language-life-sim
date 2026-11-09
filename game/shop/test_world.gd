extends SceneTree
func _init() -> void:
	call_deferred("run")

func aim(scene, target: String) -> void:
	var shop = scene.shopping
	var point := Vector3.ZERO
	if shop.world.items.has(target): point = shop.world.items[target].global_position+Vector3(0,0.12,0)
	elif shop.world.anchors.has(target): point = shop.world.anchors[target].global_position
	elif shop.home_anchors.has(target): point = shop.home_anchors[target].global_position
	elif target == "vendor": point = shop.world.actors.vendor.global_position+Vector3(0,1.2,0)
	else:
		for node in shop.world.find_children("*","StaticBody3D",true,false):
			if node.get_meta("target_id","") == target: point = node.global_position
	scene.player.position = Vector3(point.x+0.65,0.9,point.z+1.5)
	if target == "shop_exit": scene.player.position = shop.world.global_position+Vector3(0,0.9,3.8)
	if target.begins_with("home_food_"): scene.player.position = Vector3(-6.25,0.9,-1.3)
	scene.player.velocity = Vector3.ZERO
	scene.player.body.rotation = Vector3.ZERO
	scene.player.head.rotation = Vector3.ZERO
	scene.player.head.position.y = 0.0
	scene.player.eyes.position = Vector3.ZERO
	scene.player.try_crouch = false
	scene.player.is_crouching = false
	scene.player.standing_collision_shape.disabled = false
	scene.player.crouching_collision_shape.disabled = true
	await physics_frame
	await physics_frame
	scene.camera.look_at(point)
	assert(scene._target() == target,"Ray misses "+target+"; hit="+scene._target()+" point="+str(point))

func run() -> void:
	var scene = load("res://game/shop/shop.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	scene._start_new()
	var shop = scene.shopping
	assert(shop.active() and shop.state.location == "shop" and scene.state.day == 2)
	assert(not scene.house.visible and shop.world.visible)
	var units: Array = scene.state.units.duplicate()
	var bread_id: int = shop.world.items.grocery_bread.get_instance_id()
	var milk_id: int = shop.world.items.grocery_milk.get_instance_id()
	await aim(scene,"grocery_bread")
	shop.interact()
	assert(shop.state.items.grocery_bread == "player")
	await aim(scene,"grocery_milk")
	shop.interact()
	assert(shop.state.items.grocery_milk == "shelf_milk")
	await aim(scene,"counter_left")
	shop.interact()
	assert(shop.state.on_counter().size() == 1)
	await aim(scene,"checkout")
	shop.interact()
	assert(shop.modal == "" and not shop.state.paid)
	assert(scene._save())
	scene._load_save()
	assert(shop.state.items.grocery_bread == "counter_left" and shop.state.location == "shop")
	await aim(scene,"shop_exit")
	shop.interact()
	assert(shop.state.location == "home" and not shop.state.delivered)
	shop.travel_shop()
	assert(shop.state.items.grocery_bread == "counter_left")
	await aim(scene,"grocery_milk")
	shop.interact()
	await aim(scene,"counter_right")
	shop.interact()
	assert(shop.state.total() == 300)
	# Optional conversation and pointing preserve FPS and grant no new vocabulary.
	await aim(scene,"vendor")
	shop.interact()
	shop.answer("what")
	assert(shop.selecting and not scene.player.is_movement_paused)
	scene._set_pause(true)
	assert(shop.selecting and scene.paused)
	scene._set_pause(false)
	var cancel := InputEventAction.new()
	cancel.action = "prologue_cancel"
	cancel.pressed = true
	shop.input(cancel)
	assert(not shop.selecting and not scene.player.is_movement_paused)
	shop.answer("what")
	await aim(scene,"grocery_bread")
	shop.interact()
	assert(not shop.selecting and shop.dialogue == "Ein Brot.")
	assert(shop.world.pointer_target == "grocery_bread")
	await aim(scene,"checkout")
	shop.interact()
	assert(shop.modal == "checkout" and scene.ui.shop_panel.visible)
	shop.handle_command("shop_cancel")
	assert(not shop.state.paid)
	shop.open_checkout()
	assert(shop.confirm_checkout())
	assert(not shop.confirm_checkout())
	assert(shop.state.contents.size() == 2)
	assert(not shop.world.items.grocery_bread.visible and not shop.world.items.grocery_milk.visible)
	assert(shop.world.items.grocery_bread.get_parent() == shop.world.items.shopping_bag)
	await aim(scene,"shopping_bag")
	shop.interact()
	assert(shop.state.held() == "shopping_bag")
	assert(scene._save())
	scene._load_save()
	assert(shop.state.held() == "shopping_bag" and shop.state.contents.size() == 2)
	await aim(scene,"shop_exit")
	shop.interact()
	assert(shop.state.delivered and shop.state.location == "home")
	assert(scene.house.visible and not shop.world.visible)
	assert(shop.state.contents.size() == 2 and shop.state.items.shopping_bag == "player")
	assert(shop.modal == "delivered")
	assert(scene._save())
	scene._load_save()
	assert(shop.state.delivered and shop.state.contents.size() == 2)
	shop.handle_command("shop_resume")
	await aim(scene,"home_bag")
	shop.interact()
	assert(shop.state.items.shopping_bag == "home_bag")
	for item in ["grocery_bread","grocery_milk"]:
		await aim(scene,"shopping_bag")
		shop.interact()
		assert(shop.modal == "unpack")
		shop.handle_command("shop_unpack:"+item)
		assert(shop.state.items[item] == "player")
		await aim(scene,"home_food_left" if item == "grocery_bread" else "home_food_right")
		shop.interact()
		assert(shop.state.held() == "")
	assert(shop.state.contents.is_empty())
	assert(scene._save())
	scene._load_save()
	assert(shop.state.items.grocery_bread == "home_food_left" and shop.state.items.grocery_milk == "home_food_right")
	assert(shop.world.items.grocery_bread.get_instance_id() == bread_id)
	assert(shop.world.items.grocery_milk.get_instance_id() == milk_id)
	assert(scene.state.units == units,"Shop awarded new vocabulary")
	print("SHOP_WORLD_BUY_RETURN_SAVE_AND_OPTIONAL_UNPACK_OK")
	scene.queue_free()
	await process_frame
	quit()
