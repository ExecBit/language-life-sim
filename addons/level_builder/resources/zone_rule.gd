@tool
extends Resource

# One line of a room's zone recipe: "this part of the room is for that".
#
# The generator used to decide this itself — storage went on the wall furthest
# from the door, presentation went between the door and the anchor — which is
# sound reasoning about a farmhouse and pure assumption about a hive, a reactor
# deck or a shrine to something that doesn't walk. So the rules moved out of the
# engine and into the archetype, where whoever is building the place can say
# what its parts are for.
#
# The engine still owns the *structural* zones — wall, corner, centre, entrance,
# travel — because those are facts about the shape of a space rather than
# claims about what it's for.

@export var zone := "work"

# How the cells are found. Five spatial primitives; the meaning you attach to
# them is yours.
@export_enum("near_anchor", "far_from_entrances", "near_entrances",
	"between_entrance_and_anchor", "remaining") var rule := "near_anchor"

# For near_anchor, in solver cells.
@export var radius := 4
# For the entrance rules: a fraction of the room's own span, so it scales with
# the room instead of assuming one.
@export_range(0.0, 1.0) var reach := 0.45

# Which zones this rule may claim from. Structural names, or a zone an earlier
# rule in the same recipe already created — recipes run in order, so later rules
# can refine earlier ones.
@export var over: PackedStringArray = PackedStringArray(["wall", "corner", "center"])
