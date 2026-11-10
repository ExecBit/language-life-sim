extends SceneTree
const State = preload("res://implementations/dormitory/game/prologue/prologue_state.gd")
const Story = preload("res://implementations/dormitory/game/prologue/story.gd")

func _init() -> void:
	var steps := Story.build()
	var old_before_sleep := {}
	for water in [true,false]:
		for breakfast in [true,false]:
			for assisted in [true,false]:
				var state = State.new()
				var count := 0
				while not state.finished:
					var step: Dictionary = steps[state.index]
					assert(state.enter(step),"Enter "+step.id)
					assert(not state.enter(step))
					if step.get("wait","") == "done": break
					var choice := ""
					if step.id == "a_greeting": choice = "hello"
					if step.id == "b_water": choice = "yes" if water else "no"
					if step.id == "f_offer": choice = "yes" if breakfast else "no"
					if step.id == "c_bag":
						if water:
							assert(not state.transfer("bag","entrance_bag","player"))
							assert(state.transfer("cup","player","surface_room"))
						assert(state.transfer("bag","entrance_bag","player"))
						assert(state.transfer("bag","player","bag_stand"))
					if step.id == "c_key":
						assert(state.transfer("room_key","lena","key_tray")) # world setdown event
						assert(state.transfer("room_key","key_tray","player"))
					if step.id == "c_welcome": old_before_sleep = state.snapshot()
					if step.id == "f_arrival":
						assert(state.held("player") == "" and state.items.room_key == "nightstand")
						assert(state.cooking.status == "available" and not state.complete(step))
						assert(state.offer_cooking() and not state.offer_cooking())
					if step.id == "f_take":
						assert(not state.complete(step))
						assert(state.transfer("bread","kitchen_shelf","player"))
					if step.id in ["f_take","f_give"] and assisted:
						var before: Dictionary = state.items.duplicate()
						state.ask_help(step.id,"repeat")
						state.ask_help(step.id,"show")
						assert(state.items == before)
					assert(state.complete(step,choice),"Complete "+step.id)
					assert(not state.complete(step,choice))
					var restored = State.new()
					assert(restored.restore(JSON.parse_string(JSON.stringify(state.snapshot())),steps.size()))
					state = restored
					count += 1
					assert(count < 30)
				assert(state.day == 2 and state.finished and state.flags.breakfast_done)
				assert(state.items.bread == "breakfast_table" and state.items.room_key == "nightstand")
				assert(state.flags.breakfast_result == ("helped" if breakfast else "declined"))
				if breakfast:
					assert(state.flags.nimm_usage == ("assisted" if assisted else "independent"))
					assert(state.flags.gib_usage == ("assisted" if assisted else "independent"))
				else:
					assert(not state.flags.has("nimm_usage") and not state.flags.has("gib_usage"))
				assert(state.completed.count("f_offer") == 1)
	# Existing day-one and finished v2 saves resume without replaying settlement.
	var legacy: Dictionary = old_before_sleep.duplicate(true)
	legacy.version = 2
	legacy.items.erase("bread")
	var migrated = State.new()
	assert(migrated.restore(JSON.parse_string(JSON.stringify(legacy)),steps.size()))
	assert(migrated.index == 7 and migrated.items.room_key == "player")
	assert(migrated.complete(steps[7]))
	assert(migrated.day == 2 and migrated.items.room_key == "nightstand")
	legacy.day = 2
	legacy.period = "morning"
	legacy.index = 9
	legacy.finished = true
	legacy.entered.append("complete")
	legacy.completed.append("e_morning")
	var resumed = State.new()
	assert(resumed.restore(JSON.parse_string(JSON.stringify(legacy)),steps.size()))
	assert(resumed.index == 8 and not resumed.finished and resumed.items.room_key == "nightstand")
	assert("complete" not in resumed.entered and "e_morning" not in resumed.completed)
	# A failed transfer remains atomic and a second held object is rejected.
	var blocked = State.new()
	assert(blocked.transfer("cup","tray","player"))
	var before: Dictionary = blocked.snapshot()
	assert(not blocked.apply_many([["move","room_key","lena","nightstand"],["move","bag","entrance_bag","player"]]))
	assert(blocked.snapshot() == before)
	var damaged: Dictionary = before.duplicate(true)
	damaged.items.bread = "player"
	assert(not State.new().restore(damaged,steps.size()))
	# Version 3 preserves already completed cooking and active accepted requests.
	var v3: Dictionary = migrated.snapshot()
	v3.version = 3
	v3.erase("cooking")
	v3.index = 15
	v3.flags.breakfast_result = "helped"
	v3.items.bread = "breakfast_table"
	var done = State.new()
	assert(done.restore(v3,steps.size()))
	assert(done.cooking.status == "completed" and done.cooking.activity == "finished")
	assert(not done.offer_cooking())
	v3.index = 11
	v3.items.bread = "player"
	var accepted = State.new()
	assert(accepted.restore(v3,steps.size()))
	assert(accepted.cooking.status == "accepted")
	assert(accepted.skip_cooking("cancelled") and not accepted.skip_cooking("again"))
	accepted.finish_without_loaf()
	assert(accepted.items.bread == "player" and accepted.cooking.activity == "finished")
	assert(accepted.flags.breakfast_result == "skipped")
	var malformed: Dictionary = accepted.snapshot()
	malformed.cooking.elapsed = -1
	assert(not State.new().restore(malformed,steps.size()))
	# New storage locations retain one key; old v4 snapshots migrate without being mutated.
	var pocket = State.new()
	assert(pocket.transfer("room_key","lena","player"))
	assert(pocket.transfer("room_key","player","player_pocket"))
	assert(pocket.transfer("cup","tray","player"))
	assert(not pocket.transfer("cup","player","player_pocket"))
	assert(not pocket.transfer("cup","player","drawer_slot"))
	assert(not pocket.transfer("cup","player","unknown_place"))
	var old_v4 = pocket.snapshot()
	old_v4.version = 4
	assert(State.new().restore(old_v4,steps.size()) and old_v4.version == 4)
	pocket.day = 2
	pocket.ensure_cooking()
	assert(pocket.complete(steps[15])) # day-two sleep safely stows the cup, preserves the pocket
	assert(pocket.items.room_key == "player_pocket" and pocket.held("player") == "")
	assert(State.new().restore(pocket.snapshot(),steps.size()))
	var invalid = pocket.snapshot()
	invalid.items.cup = "drawer_slot"
	assert(not State.new().restore(invalid,steps.size()))
	print("DORMITORY_STATE_8_ROUTES_STORAGE_V2_V3_V4_MIGRATION_OK")
	quit()
