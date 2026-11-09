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
	room_door = CogitoDoor.new()
	room_door.position = Vector3(1.1,0,-1.0)
	room_door.open_rotation = Vector3(0,-90,0)
	room_door.door_speed = 5.0
	room_door.forced_rotation_axis = CogitoDoor.ForcedRotationAxis.AxisY
	h.add_child(room_door)
	var leaf = h.body("room_door",Vector3(0,1.2,1),Vector3(0.12,2.4,2),room_door)
	h.furniture.room_door = leaf
	h.visual(leaf,BoxMesh.new(),Vector3.ZERO,Vector3(0.12,2.4,2),Color("967550"))
	h.visual(leaf,SphereMesh.new(),Vector3(-0.1,0,0.65),Vector3.ONE*0.09,Color("e3c477"))
	room_door.door_state_changed.connect(func(value): controller.state.flags.room_door_open = value; controller._save())
	h.box(Vector3(1.1,1.6,-1.5),Vector3(0.2,3.2,1.0),Color("dfddd2"))
	h.box(Vector3(1.1,1.6,1.25),Vector3(0.2,3.2,0.5),Color("dfddd2"))
	h.box(Vector3(1.1,2.8,0),Vector3(0.2,0.8,3.0),Color("dfddd2"))
	# Closed neighbors' rooms establish the dormitory without additional interiors.
	for pair in [["Anna",-0.0],["02",-3.0]]:
		h.box(Vector3(pair[1],1.15,-5.84),Vector3(0.85,2.3,0.12),Color("766851"),false)
		var label := Label3D.new()
		label.text = pair[0]
		label.position = Vector3(pair[1],1.65,-5.74)
		label.font_size = 36
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
	room_door.is_open = controller.state.flags.get("room_door_open",false)
	room_door.is_moving = false
	room_door.set_state()
	if controller.state.flags.get("lamp_on",false) != lamp.is_on:
		if controller.state.flags.get("lamp_on",false): lamp.switch_on()
		else: lamp.switch_off()
	refresh()

func interact(target: String) -> bool:
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
