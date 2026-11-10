extends SceneTree
func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://game/shop/shop.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	scene._start_new()
	var shop = scene.shopping
	assert(shop.take_item("grocery_bread"))
	assert(shop.place_item("counter_left"))
	assert(shop.take_item("grocery_milk"))
	assert(shop.place_item("counter_right"))
	shop.open_checkout()
	assert(shop.confirm_checkout())
	assert(shop.take_item("shopping_bag"))
	shop.travel_home()
	assert(shop.state.delivered and shop.state.contents.size() == 2)
	assert(scene._save())
	await create_timer(0.3).timeout
	scene.queue_free()
	await process_frame
	# Rebuild the world from disk, not just the RefCounted state or existing nodes.
	scene = load("res://game/prologue/prologue.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	assert(scene._save_valid())
	scene._load_save()
	shop = scene.shopping
	assert(shop.active() and shop.state.location == "home")
	assert(shop.state.delivered and shop.state.contents.size() == 2)
	assert(shop.state.held() == "shopping_bag")
	for item in shop.state.GOODS:
		assert(not shop.world.items[item].visible)
		assert(shop.world.items[item].get_parent() == shop.world.items.shopping_bag)
	assert(shop.world.items.shopping_bag.get_parent() == scene.held)
	assert(not shop.state.checkout())
	print("SHOP_NEW_SCENE_RESTART_PRESERVES_PACKED_DELIVERY_OK")
	scene.queue_free()
	await process_frame
	quit()
