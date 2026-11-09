extends Node
## Thin scenario adapter: Cogito owns furniture behavior/UI; PrologueState owns item locations.
const InventoryPanel = preload("res://addons/cogito/InventoryPD/UiScenes/InventoryUI.tscn")
var controller: Node3D
var room_door: CogitoDoor
var lamp: CogitoSwitch
var storage: CogitoContainer
var panel: PanelContainer
var inventory_ui: InventoryUI
var inventory := CogitoInventory.new()
var mode := ""
var deposit: Button

func _ready() -> void:
	var h = controller.house
	for id in h.Layout.ROOMS:
		var data: Dictionary = h.Layout.ROOMS[id]
		var door := CogitoDoor.new()
		var side: float = data.side
		door.position = Vector3(side*1.1,0,data.door_z-side*0.45)
		door.open_rotation = Vector3(0,90,0)
		door.door_speed = 5.0
		door.forced_rotation_axis = CogitoDoor.ForcedRotationAxis.AxisY
		h.add_child(door)
		var target: String = "room_door" if id == "bedroom" else "door_"+id
		var leaf = h.body(target,Vector3(0,1.05,side*0.45),Vector3(0.08,2.1,0.9),door)
		h.furniture[target] = leaf
		h.doors[id] = door
		h.visual(leaf,BoxMesh.new(),Vector3.ZERO,Vector3(0.08,2.1,0.9),Color("967550"))
		h.visual(leaf,SphereMesh.new(),Vector3(-side*0.08,0,side*0.3),Vector3.ONE*0.07,Color("e3c477"))
		var flag: String = "room_door_open" if id == "bedroom" else "door_open:"+id
		door.door_state_changed.connect(func(value): controller.state.flags[flag] = value; controller._save())
		if id == "bedroom": room_door = door
		var label := Label3D.new()
		label.text = data.label
		label.position = Vector3(side*0.98,2.25,data.door_z)
		label.rotation.y = -side*PI/2
		label.font_size = 26
		label.pixel_size = 0.002
		h.add_child(label)
	lamp = CogitoSwitch.new()
	var light := OmniLight3D.new()
	light.position = Vector3(4.8,1.6,-2.6)
	light.light_color = Color("ffd69a")
	light.omni_range = 4
	light.light_energy = 2
	h.add_child(light)
	lamp.nodes_to_show_when_on.assign([light])
	h.add_child(lamp)
	var base = h.body("room_lamp",Vector3(4.8,1.05,-2.6),Vector3(0.3,0.35,0.3),lamp)
	h.furniture.room_lamp = base
	h.visual(base,CylinderMesh.new(),Vector3.ZERO,Vector3(0.28,0.3,0.28),Color("d9ac62"))
	lamp.switched.connect(func(value): controller.state.flags.lamp_on = value; controller._save())
	storage = CogitoContainer.new()
	storage.name = "PersonalDrawer"
	storage.position = Vector3(3.05,0.52,-4.72)
	storage.display_name = "Тумба"
	var animator := AnimationPlayer.new()
	animator.name = "AnimationPlayer"
	storage.add_child(animator)
	var lib := AnimationLibrary.new()
	var opening := Animation.new()
	opening.length = 0.35
	var track := opening.add_track(Animation.TYPE_VALUE)
	opening.track_set_path(track,NodePath(".:position"))
	opening.track_insert_key(track,0.0,storage.position)
	opening.track_insert_key(track,0.35,storage.position+Vector3(0,0,0.4))
	lib.add_animation("open",opening)
	animator.add_animation_library("",lib)
	storage.uses_animation = true
	storage.open_animation = "open"
	storage.use_reverse_open_as_close_anim = true
	storage.inventory_data = inventory
	h.add_child(storage)
	var drawer = h.body("drawer",Vector3.ZERO,Vector3(0.95,0.25,0.15),storage)
	h.furniture.drawer = drawer
	h.visual(drawer,BoxMesh.new(),Vector3.ZERO,Vector3(0.95,0.25,0.15),Color("c3a078"))
	var anchor := Marker3D.new()
	anchor.position = Vector3(0,0.17,-0.1)
	storage.add_child(anchor)
	h.anchors.drawer_slot = anchor
	storage.toggle_inventory.connect(func(_owner): open("drawer_slot"))
	panel = controller.ui.centered(Vector2(430,290))
	var column := VBoxContainer.new()
	panel.add_child(column)
	inventory_ui = InventoryPanel.instantiate()
	inventory_ui.inventory_name = "Вещи"
	column.add_child(inventory_ui)
	inventory.inventory_size = Vector2i(1,1)
	inventory.inventory_slots.resize(1)
	inventory.inventory_interact.connect(_slot_clicked)
	inventory_ui.set_inventory_data(inventory)
	deposit = controller.ui.button(column,"Убрать предмет из руки", "fixture_deposit")
	controller.ui.button(column,"Закрыть · I / Esc","fixture_close")
	panel.hide()

func sync() -> void:
	for id in controller.house.doors:
		var door = controller.house.doors[id]
		var flag: String = "room_door_open" if id == "bedroom" else "door_open:"+id
		door.is_open = controller.state.flags.get(flag,false)
		door.is_moving = false
		door.set_state()
	if controller.state.flags.get("lamp_on",false) != lamp.is_on:
		if controller.state.flags.get("lamp_on",false): lamp.switch_on()
		else: lamp.switch_off()
	refresh()

func interact(target: String) -> bool:
	if target.begins_with("door_") and controller.house.doors.has(target.trim_prefix("door_")):
		controller.house.doors[target.trim_prefix("door_")].interact(controller.player.player_interaction_component)
		return true
	match target:
		"room_door": room_door.interact(controller.player.player_interaction_component)
		"room_lamp": lamp.interact(controller.player.player_interaction_component)
		"drawer": storage.interact(controller.player.player_interaction_component)
		_: return false
	return true

func open(location: String) -> void:
	if controller.communication.conversation_open: controller.communication.close()
	mode = location
	if mode == "drawer_slot": storage.open()
	panel.show()
	controller.pointer = true
	refresh()
	controller._controls()

func close() -> void:
	if mode == "drawer_slot": storage.close()
	mode = ""
	panel.hide()
	controller.pointer = false
	controller._controls()

func refresh() -> void:
	if inventory_ui == null: return
	inventory.inventory_slots[0] = null
	for id in controller.state.items:
		if controller.state.items[id] != mode: continue
		var item := InventoryItemPD.new()
		item.name = {"room_key":"Schlüssel","cup":"Tasse","bell":"Glocke"}.get(id,id)
		item.icon = load("res://game/prologue/key.svg") if id == "room_key" else load("res://game/prologue/bag.svg")
		item.is_unique = true
		var slot := InventorySlotPD.new()
		slot.inventory_item = item
		slot.origin_index = 0
		inventory.inventory_slots[0] = slot
	inventory_ui.inventory_name = "Карман · ключ" if mode == "player_pocket" else "Тумба · ключ"
	inventory_ui.label.text = inventory_ui.inventory_name
	inventory.inventory_updated.emit(inventory)
	var held_item: String = controller.state.held("player")
	deposit.disabled = held_item == "" or held_item != "room_key" or mode in controller.state.items.values() or held_item == "bag"

func _slot_clicked(_inventory, _index: int, _button: int) -> void:
	for id in controller.state.items:
		if controller.state.items[id] == mode:
			if not controller.state.transfer(id,mode,"player"): controller.ui.notify("Сначала освободите руку.")
			changed()
			return

func put_held() -> void:
	var id: String = controller.state.held("player")
	if not deposit.disabled and controller.state.transfer(id,"player",mode): changed()

func changed() -> void:
	controller.house.sync_items(controller.state,controller.held)
	refresh()
	controller._save()
