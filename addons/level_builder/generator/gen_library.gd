@tool
extends Object

# Everything the generator can build with, loaded from disk. Users extend the
# generator by dropping .tres files in here — no script required, same deal as
# the layer roles and placement profiles.
#
# Filename prefix is the type: kit_, prop_, room_, level_, poi_, world_, brief_.

const DIR := "res://addons/level_builder/defaults/generation"

static var _cache := {}


static func refresh() -> void:
	_cache.clear()


static func _load_prefixed(prefix: String) -> Array[Resource]:
	if _cache.has(prefix):
		var cached: Array[Resource] = _cache[prefix]
		return cached
	var found: Array[Resource] = []
	var dir := DirAccess.open(DIR)
	if dir:
		var files := dir.get_files()
		files.sort()  # alphabetical = deterministic, whatever the filesystem thinks
		for file in files:
			if not (file.begins_with(prefix) and file.ends_with(".tres")):
				continue
			var res: Resource = load(DIR + "/" + file)
			if res:
				found.append(res)
	_cache[prefix] = found
	return found


static func kits() -> Array[Resource]:
	return _load_prefixed("kit_")


static func props() -> Array[Resource]:
	return _load_prefixed("prop_")


static func room_archetypes() -> Array[Resource]:
	return _load_prefixed("room_")


static func activity_groups() -> Array[Resource]:
	return _load_prefixed("group_")


static func activity_group(id: String) -> Resource:
	for group in activity_groups():
		if String(group.group_id) == id:
			return group
	return null


static func level_archetypes() -> Array[Resource]:
	return _load_prefixed("level_")


static func poi_archetypes() -> Array[Resource]:
	return _load_prefixed("poi_")


static func world_archetypes() -> Array[Resource]:
	return _load_prefixed("world_")


static func briefs() -> Array[Resource]:
	return _load_prefixed("brief_")


static func palettes() -> Array[Resource]:
	return _load_prefixed("palette_")


static func palette(id: String) -> Resource:
	var all := palettes()
	for entry in all:
		if String(entry.palette_id) == id:
			return entry
	return all[0] if not all.is_empty() else null


static func _by_id(list: Array[Resource], id: String) -> Resource:
	for res in list:
		if String(res.archetype_id) == id:
			return res
	return list[0] if not list.is_empty() else null


static func kit(kit_id: String) -> Resource:
	for k in kits():
		if String(k.kit_id) == kit_id:
			return k
	var all := kits()
	return all[0] if not all.is_empty() else null


static func room_archetype(id: String) -> Resource:
	return _by_id(room_archetypes(), id)


static func level_archetype(id: String) -> Resource:
	return _by_id(level_archetypes(), id)


static func poi_archetype(id: String) -> Resource:
	return _by_id(poi_archetypes(), id)


static func world_archetype(id: String) -> Resource:
	return _by_id(world_archetypes(), id)


# Furniture carrying a tag, with a resolvable scene. Kit pieces are excluded —
# a floor tile is not a candidate for "put a bed here".
#
# A palette may rule candidates out by style tag, but never all of them: if the
# filter would leave a role with nothing, it's ignored. Style dresses a room, it
# doesn't get to take the room's anchor away.
static func props_with_tag(tag: String, palette: Resource = null) -> Array[Resource]:
	var found: Array[Resource] = []
	for prop in props():
		if prop.is_prop and prop.has_tag(tag) and prop.scene() != null:
			found.append(prop)
	if palette == null or found.is_empty():
		return found
	var allowed: Array[Resource] = []
	for prop in found:
		if not palette.excludes(prop):
			allowed.append(prop)
	return allowed if not allowed.is_empty() else found


# Scopes this install can actually generate, in order. The dock builds its
# dropdown from this rather than from the enum, so a scope with no presets is
# absent instead of present-and-broken — which is what a Lite cut looks like,
# and also what a project looks like once somebody curates their own briefs.
static func scopes_with_briefs() -> Array[int]:
	var found: Array[int] = []
	for brief in briefs():
		var scope := int(brief.scope)
		if not scope in found:
			found.append(scope)
	found.sort()
	return found


static func briefs_for_scope(scope: int) -> Array[Resource]:
	var found: Array[Resource] = []
	for brief in briefs():
		if int(brief.scope) == scope:
			found.append(brief)
	return found
