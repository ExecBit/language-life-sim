@tool
extends Resource

# A point of interest at world scale: a plot on the map and the building that
# stands on it. Interiors are lazy — the marker is real, the level behind it
# gets generated now or on demand.

@export var archetype_id := "outpost"
@export var display_name := "Outpost"
# Used when interiors are deferred; with interiors on, the plot fits the level.
@export var plot_modules := Vector2i(6, 6)
@export var level_archetype_id := "fort"
@export var weight := 1.0
