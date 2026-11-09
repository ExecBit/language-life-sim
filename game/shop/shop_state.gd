extends RefCounted

const VERSION := 1
const GOODS := ["grocery_bread","grocery_milk"]
const PRICES := {"grocery_bread":180,"grocery_milk":120}
const SHOP_ANCHORS := ["shelf_bread","shelf_milk","counter_left","counter_right","packing_stand"]
const HOME_ANCHORS := ["home_bag","home_food_left","home_food_right","home_staging","home_desk","home_kitchen"]
var started := false
var location := "home"
var paid := false
var delivered := false
var delivery_acknowledged := false
var seller_greeted := false
var items := {"grocery_bread":"shelf_bread","grocery_milk":"shelf_milk","shopping_bag":"hidden"}
var contents: Array[String] = []

func held() -> String:
	for item in items:
		if items[item] == "player": return item
	return ""

func here(anchor: String) -> bool:
	return anchor in (SHOP_ANCHORS if location == "shop" else HOME_ANCHORS)

func take(item: String) -> bool:
	if not items.has(item) or held() != "" or not here(str(items[item])): return false
	items[item] = "player"
	return true

func place(anchor: String) -> bool:
	var item := held()
	if item == "" or not here(anchor) or anchor in items.values(): return false
	if item == "shopping_bag" and anchor not in ["packing_stand","home_bag"]: return false
	if item in GOODS and anchor in ["packing_stand","home_bag"]: return false
	items[item] = anchor
	return true

func on_counter() -> Array[String]:
	var result: Array[String] = []
	for item in GOODS:
		if items[item] in ["counter_left","counter_right"]: result.append(item)
	return result

func total() -> int:
	var result := 0
	for item in on_counter(): result += int(PRICES[item])
	return result

static func price(cents: int) -> String:
	return "%d,%02d €" % [cents/100,cents%100]

func checkout() -> bool:
	if not started or location != "shop" or paid or held() != "" or on_counter().size() != 2: return false
	# Commit all three ownership changes together; repeat confirmation is a no-op.
	paid = true
	contents.assign(GOODS)
	for item in GOODS: items[item] = "in:shopping_bag"
	items.shopping_bag = "packing_stand"
	return true

func travel(destination: String) -> bool:
	if destination not in ["home","shop"] or destination == location: return false
	if destination == "home" and not paid and held() in GOODS: return false
	started = true
	location = destination
	if destination == "home" and paid and items.shopping_bag == "player" and contents.size() == 2:
		delivered = true
	return true

func unpack(item: String) -> bool:
	if location != "home" or not delivered or held() != "" or items.shopping_bag != "home_bag": return false
	if item not in contents or items.get(item) != "in:shopping_bag": return false
	contents.erase(item)
	items[item] = "player"
	return true

func snapshot() -> Dictionary:
	return {"version":VERSION,"started":started,"location":location,"paid":paid,"delivered":delivered,
		"delivery_acknowledged":delivery_acknowledged,"seller_greeted":seller_greeted,
		"items":items.duplicate(),"contents":contents.duplicate()}

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION: return false
	for field in ["started","paid","delivered","delivery_acknowledged","seller_greeted"]:
		if not data.get(field) is bool: return false
	if data.get("location") not in ["home","shop"] or not data.get("items") is Dictionary or not data.get("contents") is Array: return false
	if data.items.size() != 3 or data.contents.size() > 2: return false
	var unique := {}
	for item in data.contents:
		if item not in GOODS or unique.has(item): return false
		unique[item] = true
	var occupied := {}
	for item in items:
		if not data.items.get(item) is String: return false
		var anchor: String = data.items[item]
		if anchor not in SHOP_ANCHORS+HOME_ANCHORS+["player","hidden","in:shopping_bag"]: return false
		if item == "shopping_bag":
			if anchor not in ["hidden","packing_stand","player","home_bag"]: return false
		else:
			if anchor == "hidden" or anchor in ["packing_stand","home_bag"]: return false
			if (anchor == "in:shopping_bag") != (item in data.contents): return false
		if anchor != "in:shopping_bag":
			if occupied.has(anchor): return false
			occupied[anchor] = item
	if not data.paid and (not data.contents.is_empty() or data.items.shopping_bag != "hidden"): return false
	if not data.paid:
		for item in GOODS:
			if data.items[item] in HOME_ANCHORS: return false
			if data.location == "home" and data.items[item] == "player": return false
	if data.paid and data.items.shopping_bag == "hidden": return false
	if data.delivered and not data.paid: return false
	if data.delivery_acknowledged and not data.delivered: return false
	if not data.started and (data.location != "home" or data.paid): return false
	started = data.started
	location = data.location
	paid = data.paid
	delivered = data.delivered
	delivery_acknowledged = data.delivery_acknowledged
	seller_greeted = data.seller_greeted
	items = data.items.duplicate()
	contents.assign(data.contents)
	return true
