@tool
extends Resource

# The "few clicks" object: scope, preset, size, seed. Ships as .tres presets in
# defaults/generation/; the Generate tab duplicates one and overrides the knobs
# before handing it to the generator.

enum Scope { ROOM, LEVEL, WORLD }

@export var brief_name := "Room"
@export var scope: Scope = Scope.ROOM
# RoomArchetype / LevelArchetype / WorldArchetype id, depending on scope
@export var archetype_id := "bedroom"
@export_range(0, 2) var size_class := 1  # 0 small, 1 medium, 2 large
@export var kit_id := "greybox"
# StylePalette id — who lives here and how well they keep it.
@export var palette_id := "lived_in"
@export_group("What kind of place")
# Three knobs that say what the creator wants rather than what the world is.
# A preset picks the vocabulary — rooms, props, style — and these say how that
# vocabulary should be arranged. They're deliberately not domain words: a
# sprawling, sparse, branching place is a warren of empty caves or a derelict
# station wing depending on which archetypes you point them at.
#
# How full the spaces are: bare shell to crammed.
@export_range(0.0, 1.0) var density := 0.5
# Tight and cellular, or open and sprawling. Biases how big spaces come out and
# how long the runs between them are.
@export_range(0.0, 1.0) var openness := 0.5
# One route through, or a warren to get lost in. Low keeps the plan walking
# outward in a line; high hangs rooms off everything and leaves dead ends.
@export_range(0.0, 1.0) var branching := 0.5

@export var rng_seed := 0
# World scope only: fill POI interiors now, or leave movable markers for later.
@export var generate_interiors := true
