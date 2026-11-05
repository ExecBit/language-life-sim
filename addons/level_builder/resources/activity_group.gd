@tool
extends Resource

# A thing people do, and everything it needs within arm's reach.
#
# A bed on its own is a prop. A bed with a chest at its foot and a rug beside it
# is somewhere somebody sleeps. The difference isn't the props — it's that they
# were placed together, as one decision, near each other.
#
# The lead goes down first and the members are placed around it. Required
# members are what the activity can't do without: if one won't fit, the whole
# group is rolled back and tried somewhere else rather than left half-built with
# an anvil on the far side of the room.

@export var group_id := "bed_set"
@export var display_name := "Bed"
# The prop the group is built around, by tag.
@export var lead_tag := "bed"
# Placed within `radius` cells of the lead. Miss one of these and the group is
# re-tried elsewhere; miss an optional one and nobody minds.
@export var required_tags: PackedStringArray = PackedStringArray()
@export var optional_tags: PackedStringArray = PackedStringArray()
@export var radius := 4  # solver cells from the lead
