extends Node
const State = preload("res://implementations/dormitory/game/shop/shop_state.gd")
const World = preload("res://implementations/dormitory/game/shop/shop_world.gd")
var controller: Node3D
var state = State.new()
var world: Node3D
var home_anchors := {}
var home_storage: Node3D
var modal := ""
var selecting := false
var dialogue := ""
var dialogue_time := 0.0
var vendor_options := false

func _ready() -> void:
	world = World.new()
	world.position.x = 40
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	controller.add_child(world)
	world.hide()
	home_storage = Node3D.new()
	controller.house.add_child(home_storage)
	var pedestal: StaticBody3D = controller.house.body("home_bag_table",Vector3(-2.8,0.36,2.6),Vector3(1.3,0.72,0.7),home_storage)
	controller.house.visual(pedestal,BoxMesh.new(),Vector3.ZERO,Vector3(1.3,0.72,0.7),Color("9c805b"))
	var positions := {"home_bag":Vector3(-3.1,0.75,2.6),"home_staging":Vector3(-2.5,0.75,2.6),
		"home_food_left":Vector3(-6.3,1.47,-3.6),"home_food_right":Vector3(-5.95,1.47,-3.6),
		"home_desk":Vector3(4.8,1,-2.6),"home_kitchen":Vector3(-2.6,1,-2.3)}
	for id in positions:
		var anchor = controller.house.body(id,positions[id],Vector3(0.28,0.025,0.28),home_storage)
		controller.house.visual(anchor,BoxMesh.new(),Vector3.ZERO,Vector3(0.28,0.02,0.28),Color("c6cbb2"))
		home_anchors[id] = anchor
	# The personal compartment must have an open front for FPS item selection.
	for body in controller.house.find_children("*","StaticBody3D",true,false):
		if body.get_meta("target_id","") == "own_pantry":
			var collider: CollisionShape3D = body.get_child(0)
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.65,0.05,0.65)
			collider.shape = shape
			collider.position.y = -0.12
	apply_location(false)

func active() -> bool:
	return state.started

func reset() -> void:
	state = State.new()
	modal = ""
	selecting = false
	dialogue = ""
	controller.ui.hide_shop_panel()
	apply_location(false)

func apply_location(move_player := false) -> void:
	controller.house.visible = state.location == "home"
	world.visible = state.location == "shop"
	home_storage.visible = state.started
	for body in home_storage.find_children("*","StaticBody3D",true,false): body.collision_layer = 1 if state.started else 0
	if move_player:
		controller.player.position = world.global_position+world.zones.spawn if state.location == "shop" else Vector3(0,0.9,3.8)
		controller.player.body.rotation = Vector3.ZERO
		controller.player.head.rotation = Vector3.ZERO
		controller.camera.rotation = Vector3.ZERO
		controller.player.velocity = Vector3.ZERO
	sync_items()
	controller.ui.shop_status.visible = state.started
	controller.ui.shop_hud.visible = state.started
	controller.ui.complete_panel.hide()
	controller.ui.dialog.hide()
	controller.ui.chapter.text = "Первые покупки · День 2 · " + ("магазин" if state.location == "shop" else "дом")
	controller.pointer = false
	controller._controls()

func sync_items() -> void:
	world.sync_shopping(state,controller.held,home_anchors)
	controller.ui.shop_status.text = "✓ сумка %d/2" % state.contents.size() if state.paid else "· касса %d/2" % state.on_counter().size()

func store_home_item() -> bool:
	var held: String = controller.state.held("player")
	if held == "": return true
	for anchor in ["surface_room","key_tray","bedside_spare","surface_common","surface_side"]:
		if anchor not in controller.state.items.values():
			if controller.state.transfer(held,"player",anchor):
				controller.house.sync_items(controller.state,controller.held)
				controller.ui.notify("Перед дорогой вещь оставлена на свободной поверхности дома.")
				return true
	return false

func travel_shop() -> void:
	if controller.state.day != 2: return
	if not controller.state.finished: controller._finish_level()
	if not store_home_item(): return
	if not state.travel("shop"): return
	modal = ""
	selecting = false
	dialogue = ""
	controller.ui.hide_shop_panel()
	controller.exploration = false
	apply_location(true)
	controller.ui.notify("Купите продукты для своей полки дома. E — взять / поставить. На кассу — по одному.")
	controller._save()

func travel_home() -> void:
	var delivered_before: bool = state.delivered
	if not state.travel("home"):
		controller.ui.notify("Верните неоплаченный товар на полку или положите на кассу. Можно уйти без покупки.")
		return
	modal = ""
	selecting = false
	dialogue = ""
	controller.ui.hide_shop_panel()
	apply_location(true)
	if state.delivered and not delivered_before: delivery_panel()
	else: controller.ui.notify("Дом. Покупки в магазине сохраняются; можно вернуться и продолжить.")
	controller._save()

func delivery_panel() -> void:
	modal = "delivered"
	controller.ui.show_shop_panel("ПЕРВЫЕ ПОКУПКИ ЗАВЕРШЕНЫ","Сумка с двумя продуктами доставлена домой.\nРазобрать её можно по желанию.",[{"id":"shop_resume","text":"Осмотреть дом"}])
	controller.pointer = true
	controller._controls()

func restore(data: Variant) -> bool:
	var candidate = State.new()
	if data != null and not candidate.restore(data): return false
	state = candidate
	modal = ""
	selecting = false
	dialogue = ""
	vendor_options = false
	controller.ui.hide_shop_panel()
	apply_location(false)
	if state.delivered and not state.delivery_acknowledged: delivery_panel()
	return true

func handle_command(id: String) -> bool:
	match id:
		"travel_shop": travel_shop()
		"shop_confirm": confirm_checkout()
		"shop_cancel": close_panel()
		"shop_resume":
			state.delivery_acknowledged = true
			close_panel()
			controller._save()
		"shop_take_bag":
			close_panel()
			take_item("shopping_bag")
		_:
			if id.begins_with("shop_unpack:"):
				var item := id.trim_prefix("shop_unpack:")
				if controller.state.held("player") == "" and state.unpack(item):
					close_panel()
					sync_items()
					controller._save()
			else: return false
	return true

func close_panel() -> void:
	modal = ""
	controller.ui.hide_shop_panel()
	controller.pointer = false
	controller._controls()

func input(event: InputEvent) -> void:
	if event.is_action_pressed("prologue_goal"):
		controller.ui.notify("Вернитесь домой с сумкой." if state.paid and not state.delivered else ("Продукты уже дома. Распаковка необязательна." if state.delivered else "Купить продукты для своей полки: ▱ + ▯. Перенесите оба товара на кассу."))
		return
	if event.is_action_pressed("prologue_cancel"):
		if modal != "":
			if modal == "delivered": handle_command("shop_resume")
			else: close_panel()
		elif selecting:
			selecting = false
			say("Hallo!",true)
		else:
			dialogue = ""
			controller.ui.dialog.hide()
		return
	for i in 6:
		if event.is_action_pressed(["prologue_one","prologue_two","prologue_three","prologue_four","prologue_five","prologue_six"][i]):
			if modal != "":
				if i < controller.ui.shop_modal_ids.size(): handle_command(controller.ui.shop_modal_ids[i])
			elif i < controller.ui.answer_ids.size(): answer(controller.ui.answer_ids[i])
			return
	if modal != "": return
	if event.is_action_pressed("prologue_cursor"):
		controller.pointer = not controller.pointer
		controller._controls()
	elif event.is_action_pressed("prologue_interact"): interact()
	elif event is InputEventMouseMotion and not controller.pointer: controller.player.on_input(event)

func say(text: String, options := false, seconds := 0.0) -> void:
	dialogue = text
	dialogue_time = seconds
	vendor_options = options
	controller.ui.display("Продавец","Вы",text,[{"id":"hello","text":"Hallo!"},{"id":"what","text":"Was ist das?"},{"id":"thanks","text":"Danke!"},{"id":"bye","text":"Tschüss!"}] if options else [])

func answer(id: String) -> void:
	if state.location != "shop" or modal != "" or controller.player.position.distance_to(world.actors.vendor.global_position) > 4.5: return
	match id:
		"what":
			selecting = true
			controller.pointer = false
			controller.ui.dialog.hide()
			controller._controls()
		"hello": say("Hallo!",true)
		"thanks": say("Bitte.",true)
		"bye": say("Tschüss!",false,3.0)

func take_item(item: String) -> bool:
	if controller.state.held("player") != "" or state.held() != "":
		controller.ui.notify("Рука занята. Сначала поставьте предмет.")
		return false
	if not state.take(item): return false
	sync_items()
	controller._save()
	return true

func place_item(anchor: String) -> bool:
	if not state.place(anchor): return false
	sync_items()
	controller._save()
	return true

func open_checkout() -> void:
	if state.paid:
		controller.ui.notify("Покупка уже оформлена. Заберите сумку со стойки.")
		return
	if state.on_counter().size() != 2:
		controller.ui.notify("На кассе %d/2. Положите оба продукта; покупку можно продолжить позже." % state.on_counter().size())
		return
	modal = "checkout"
	controller.ui.show_shop_panel("КАССА","Σ    %s" % state.price(state.total()),[{"id":"shop_confirm","text":"Купить · "+state.price(state.total())},{"id":"shop_cancel","text":"Вернуться к выбору"}])
	controller.ui.add_receipt_icons()
	controller.pointer = true
	controller._controls()

func confirm_checkout() -> bool:
	if modal != "checkout" or controller.state.held("player") != "": return false
	for item in state.GOODS:
		if not is_instance_valid(world.items.get(item)) or not world.items[item].visible: return false
		if world.items[item].get_parent() != world.anchors.get(state.items[item]): return false
	if not state.checkout(): return false
	close_panel()
	sync_items()
	say("Danke!",false,3.0)
	controller.ui.notify("Два продукта упакованы. E — забрать сумку со стойки.")
	controller._save()
	return true

func bag_panel() -> void:
	var choices: Array = [{"id":"shop_take_bag","text":"Взять сумку"}]
	for item in state.contents:
		choices.append({"id":"shop_unpack:"+item,"text":"Достать"})
	choices.append({"id":"shop_cancel","text":"Отмена"})
	modal = "unpack"
	controller.ui.show_shop_panel("ПОКУПКИ","В сумке: %d/2. Можно разбирать по одному." % state.contents.size(),choices)
	controller.pointer = true
	controller._controls()

func interact() -> void:
	if modal != "": return
	var target: String = controller._target()
	if selecting:
		if target in state.GOODS and is_instance_valid(world.items[target]) and world.items[target].visible:
			selecting = false
			world.point("vendor",target)
			say("Ein Brot." if target == "grocery_bread" else "Das ist Milch.",true)
		else: controller.ui.notify("E — выбрать видимый товар. Backspace — отмена.")
		return
	if state.location == "shop":
		if target == "shop_exit" or Vector2(controller.player.position.x-world.global_position.x,controller.player.position.z-4.5).length() < 1.1:
			travel_home()
			return
		if target == "vendor":
			world.actors.vendor.face(controller.player.global_position)
			say("Hallo!",true)
			return
		if target == "checkout":
			open_checkout()
			return
	else:
		if Vector2(controller.player.position.x,controller.player.position.z-7.5).length() < 1.6:
			travel_shop()
			return
		if target == "shopping_bag" and state.items.shopping_bag == "home_bag" and state.held() == "" and not state.contents.is_empty():
			bag_panel()
			return
	if world.items.has(target):
		take_item(target)
		return
	if state.held() != "":
		if target == "shop_counter":
			for anchor in ["counter_left","counter_right"]:
				if anchor not in state.items.values():
					place_item(anchor)
					return
		elif target == "own_pantry":
			for anchor in ["home_food_left","home_food_right"]:
				if anchor not in state.items.values():
					place_item(anchor)
					return
		elif target in ["table_common","table_room","home_bag_table"]:
			var anchor: String = {"table_common":"home_kitchen","table_room":"home_desk","home_bag_table":"home_bag" if state.held() == "shopping_bag" else "home_staging"}[target]
			place_item(anchor)
		else: place_item(target)
		return
	if state.location == "home":
		if target == "lena": controller.ui.display("Лена","Вы","Hallo!",[])
		else: controller._object_action(target)

func tick(delta: float) -> void:
	if dialogue_time > 0:
		dialogue_time -= delta
		if dialogue_time <= 0:
			dialogue = ""
			controller.ui.dialog.hide()
	if state.location == "shop" and not state.seller_greeted and controller.player.position.distance_to(world.actors.vendor.global_position) < 3.5:
		state.seller_greeted = true
		say("Hallo!",false,3.5)
		controller._save()
	var target: String = controller._target()
	controller.ui.prompt.text = ""
	if modal != "": return
	if selecting:
		controller.ui.prompt.text = "E — выбрать видимый товар · Backspace — отмена"
	elif state.location == "shop" and (target == "shop_exit" or Vector2(controller.player.position.x-world.global_position.x,controller.player.position.z-4.5).length() < 1.1):
		controller.ui.prompt.text = "E — вернуться домой"
	elif state.location == "home" and Vector2(controller.player.position.x,controller.player.position.z-7.5).length() < 1.6:
		controller.ui.prompt.text = "E — в магазин"
	elif target == "checkout": controller.ui.prompt.text = "E — касса · "+state.price(300 if state.paid else state.total())
	elif target == "vendor": controller.ui.prompt.text = "E — обратиться · Backspace — закончить разговор"
	elif target in state.GOODS: controller.ui.prompt.text = "E — взять" + (" · "+state.price(int(state.PRICES[target])) if state.location == "shop" and not state.paid else "")
	elif target == "shopping_bag": controller.ui.prompt.text = "E — сумка · %d/2" % state.contents.size()
	elif state.held() != "" and (world.anchors.has(target) or home_anchors.has(target) or target in ["shop_counter","own_pantry","home_bag_table","table_common","table_room"]): controller.ui.prompt.text = "E — поставить"
