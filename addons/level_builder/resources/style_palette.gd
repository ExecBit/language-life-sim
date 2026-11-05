@tool
extends Resource

# Who lives here now, and how long since anyone cared for it.
#
# The functional layer decides what a room is FOR and where things go. This
# layer decides what those things look like and how much mess is around them —
# and it runs afterwards, on purpose. Get the smithy working first, then decide
# whether it's a working forge or a burnt-out one. One floor plan, several very
# different places.
#
# The knobs are description, the tags are mechanism. Nothing here can move a
# prop into a doorway or take a room's anchor away: style dresses the room, it
# doesn't re-plan it.

@export var palette_id := "lived_in"
@export var display_name := "Lived in"

@export_group("Feel")
@export_range(0.0, 1.0) var wealth := 0.5
@export_range(0.0, 1.0) var cleanliness := 0.5
@export_range(0.0, 1.0) var occupancy := 0.5
@export_range(0.0, 1.0) var damage := 0.0
@export_range(0.0, 1.0) var age := 0.5
@export var faction := ""
@export var mood := ""

@export_group("What it picks")
# Props carrying one of these win the coin toss when several fit the same role —
# a ruined room reaches for the broken crate over the intact one. A preference,
# never a filter: it can't leave a room without the thing it's for.
@export var prefer_style_tags: PackedStringArray = PackedStringArray()
# These are a filter, and they're sharp. Leave empty unless you're sure every
# role still has something to offer.
@export var exclude_style_tags: PackedStringArray = PackedStringArray()

@export_group("How much mess")
# Multiplies the clutter an archetype asks for. 0 is a swept room.
@export_range(0.0, 3.0) var clutter_density := 1.0
# Rubble, debris, scorch marks — scattered after everything else is placed.
@export var condition_tags: PackedStringArray = PackedStringArray()
# Roughly how many condition props per 100 solver cells of floor.
@export_range(0.0, 12.0) var condition_density := 0.0
# Condition props land in clusters this wide rather than evenly — mess pools in
# corners and against walls, it doesn't sprinkle.
@export var cluster_radius := 3


func prefers(prop: Resource) -> bool:
	for tag in prefer_style_tags:
		if tag in prop.style_tags:
			return true
	return false


func excludes(prop: Resource) -> bool:
	for tag in exclude_style_tags:
		if tag in prop.style_tags:
			return true
	return false
