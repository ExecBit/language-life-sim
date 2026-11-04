# Tavern layout (TAV-03 redesign, PR #16 review round 3)

The source of truth for the tavern's permanent room. The user approved a zoned 16 x 12 m floor
plan; every position below is derived from the measured imported model boxes, not from the ASCII
sketch. Coordinates: X increases east, Z increases south (the entrance side). Ground is y = 0.

## Room footprint

Interior 16 x 12 m: X -8.0 .. +8.0, Z -6.0 .. +6.0. Walls are 4 m KayKit modules, 0.5 m thick,
4.0 m tall, centred on the grid lines x/z = -8.25, -6/-2/+2/+6 (X walls) and -4/0/+4 (Z walls).
The RoomShell (scenes/main.tscn) carries the real colliders; wall meshes are visual only.

- Entrance: south wall, doorway module centred at x = -2 (span -4..0), spawn just inside at
  (-2, 0, 4.6) facing north.
- Central circulation: entrance aisle north along x = -2, branching west to the bar and north-east
  to the guest tables; the widest open lane runs x -4.9 .. -0.9 (4 m) between the bar front and
  the first guest table.

## Functional zones

| Zone | Where | Pieces (stable ids) |
| --- | --- | --- |
| Kitchen / stock | north-west, x -8..-2, z -6..-3.7 | `kitchen_fridge`, `kitchen_stove`, `service_counter`, `kitchen_cabinet`, `stove_cabinet` |
| Bar | west wall, z -1.0..+4.1 | `bar_counter_1`, `bar_counter_2`, `bar_stool_1`, `bar_stool_2` (der Ritter behind the south end) |
| Guest seating | middle/east | `guest_table_1` (round 3 m), `guest_table_2` (round small), `guest_table_3` (medium 2 m), chairs tucked per measured rim |
| Lounge | north-east corner | `lounge_sofa`, `lounge_table`, `lamp_lounge` |
| Decoration | sparse, after layout | `menu_stand`, two pictures, `rug_t1` |

## Measured model footprints (world AABB at yaw, from .local/measure_tavern16x12.gd)

| Model | Size (w x h x d) | Pivot note |
| --- | --- | --- |
| wall / wall_doorway | 4.0 x 4.0 x 0.5 | centred; doorway spans -4..0 at x = -2 |
| wall_window_open | 0.5 x 4.0 x 4.0 | west wall, z = +4 |
| kitchencounter_straight_A | 2.0 x 1.0 x 2.04 | top at y = 1.00; 2.04 deep |
| stove_single | 2.0 x 1.21 x 2.29 | deeper than wide at yaw 0 |
| fridge_A | 2.0 x 2.50 x 2.24 | 2.24 deep |
| kitchencabinet | 2.0 x 2.0 x 1.04 | hangs at y 2..4, needs `ground: false` |
| crate / crate_potatoes | 2.0 x 0.8/0.97 x 2.0 | full 2 m footprint |
| pillar_A | 0.6 x 4.1 x 0.6 | |
| couch | 3.0 x 1.22 x 1.6 | back offset differs by yaw (0.75 vs 0.85) |
| table_round_A | 3.0 x 1.0 x 3.0 | top y = 1.00, the `on_table` station |
| table_round_A_small | 1.5 x 1.0 x 1.5 | top y = 1.00 |
| table_medium | 2.0 x 1.0 x 2.0 | top y = 1.00 |
| chair_A | 0.75 x 1.21 x 0.80 | tucked 0.02..0.15 into a table rim |
| chair_stool | 0.75 x 0.50 x 0.75 | |
| lamp_standing | 1.0 x 2.52 x 1.00 | |
| pictureframe_large_A | 1.0 x 1.2 x 0.2 | modelled around its own centre, `ground: false` |
| Knight.glb | 2.69 x 2.47 x 2.58 | AABB includes weapon sweep, far larger than the body |
| Mage.glb | 2.43 x 3.00 x 2.54 | same caveat |
| Rogue_Hooded.glb | 2.94 x 2.25 x 1.55 | origin 1.94 m from the box's west edge |
| food items | ~0.75 x 0.7 x 0.75 | |

## Stations (authored, stable)

- `on_counter` -> `service_counter` (kitchen prep counter, west wall of the kitchen, top y = 1.00).
  Default station of the tavern world: what a record offers without saying where stands here,
  which keeps bring tasks ("bring it to the table") semantically clean.
- `in_fridge` -> `kitchen_fridge` (north wall of the kitchen, item at the fridge's south face).
- `on_table` -> `guest_table_1` (round 3 m table, x = 0.6, z = -2.2). Also t02's delivery target.
- A placement slot may address its anchor by `"anchor_id"` (an interior instance id) instead of a
  bare model path; `delivery_target` may carry `"instance_id"`. Model-path addressing stays valid
  for the legacy practice world, which builds no interior and spawns its own anchors.

## NPCs

- der Ritter (owner): (-6.4, 0, 4.4), facing north along the bar from its south end - the counter
  run is 2.04 m deep and flush to the west wall, so there is no gap behind it; the end of the bar
  is the spot that reads as "the person serving" without putting him inside a wall.
- der Mage (worker): (-1.8, 0, -4.6), facing west toward the stove and the prep counter. The pick
  box of a KayKit character is 2.4-2.9 m across, far larger than the body, and every kitchen-interior
  spot tested sat inside the walk-and-aim corridor from the entrance to the fridge station - the
  crosshair hit the worker instead of the item. This wall-side spot keeps every spawn-to-station
  line clear of the box.
- der Gast (guest): (3.1, 0, -2.2), facing west toward `guest_table_1`.

## Deliberate contacts (intended, not defects)

Chairs tucked into table rims (0.02..0.15 m), the rug under `guest_table_1`, cabinets hung on
walls, counter halves joined end to end, props sitting on stations, the sofa's back 0.05 m into
the north wall line, NPC weapon-sweep AABBs grazing the bar end / stove line (bodies clear).

## Access rules

Every spawn, station anchor, the carry tray (-2.2, 0.85, 1.6) and each guest table is reachable on
foot: the only solid pieces are the bar counters and the prep counter, all flush against walls, and
no piece of task furniture is solid. The entrance-to-service lane stays >= 4 m wide; table gaps
stay >= 1.3 m. The stock crate from the first draft was cut: its north-wall footprint sat inside the
walk-and-aim corridor to the fridge station, and a smaller, coherent kitchen reads better.
