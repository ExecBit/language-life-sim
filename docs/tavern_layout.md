# Tavern layout — fixed furniture compositions

The permanent TAV-03 room is authored from six scene instances in `data/room/lex01_room.json`:
one kitchen, one bar, three copies of the guest-table composition, and one lounge. Local furniture
transforms live in the reusable PackedScenes under `scenes/furniture_groups/`; the JSON positions
only each group. No coordinates are generated at runtime.

Coordinates use the existing 16 × 12 m interior: X increases east and Z increases south; the ground
is y = 0. The entrance is in the south wall near x = -2. The central northbound route stays open
between the west-wall bar and the guest-table groups.

## Fixed composition placements

| Composition | Root position (m) | Stable member IDs |
| --- | ---: | --- |
| Kitchen | (-6.0, 0, -4.87) | `kitchen_fridge`, `kitchen_stove`, `service_counter`, `kitchen_storage_prep`, `kitchen_storage_stove` |
| Bar | (-5.75, 0, 0) | `bar_counter_1`, `bar_counter_2`, `bar_stool_1`, `bar_stool_2` |
| Guest table 1 | (0.6, 0, -2.5) | `guest_table_1`, `guest_table_1_chair_north`, `guest_table_1_chair_south` |
| Guest table 2 | (5.0, 0, -2.5) | `guest_table_2`, matching north/south chair IDs |
| Guest table 3 | (5.0, 0, 1.35) | `guest_table_3`, matching north/south chair IDs |
| Lounge | (5.5, 0, -5.15) | `lounge_sofa`, `lounge_table`, `lounge_lamp` |

The guest composition uses two chairs rather than four: with the actual 0.8 m chair depth and
small table dimensions this leaves a continuous entrance aisle and separates the three groups.
The lounge sofa faces south, with its back against the north wall and the small table in front.
The kitchen composition keeps fridge, stove, preparation counter and two storage cabinets in one
work area. The bar sections join end-to-end; stools face the customer side. A roughly 1.2 m service
strip remains between the bar and west wall.

## Measured KayKit bounds and pivot treatment

Bounds were read from imported glTF mesh AABBs with Godot 4.7.1 after applying the model's child
transforms. The bounds below are world-aligned dimensions at the authored group yaw; they include
the source pivot offset, so local transforms place the visible mesh, not an assumed centred proxy.

| Asset | Bounds W×H×D (m) | Pivot / placement note |
| --- | ---: | --- |
| `table_round_A_small` | 1.50×1.00×1.50 | centered in X/Z; base at y=0; tabletop at y=1.00 |
| `chair_A` | 0.75×1.208×0.796 | source bottom is ~0; rotate north chair 180° and south chair 0° toward table |
| `kitchencounter_straight_A` | 2.042×1.00×2.00 at yaw 90° | source Z pivot is offset by ~0.021 m; visible base sits on floor |
| `chair_stool` | 0.75×0.50×0.75 | base at y=0; yaw 90° faces west toward bar |
| `stove_single` | 2.00×1.208×2.288 | source bottom is ~0; adjacent to fridge in kitchen run |
| `fridge_A` | 2.00×2.50×2.24 | source bottom is 0; front faces south |
| `kitchencabinet` | 2.00×2.00×1.042 | mesh starts at y=2; local `ground=false` keeps it wall-mounted |
| `couch` | 3.00×1.224×1.60 | yaw 180° puts back against the north wall; box reaches the wall line |
| `table_medium` (unused in groups) | 2.00×1.00×2.00 | centered, base at y=0 |

The guest table1 scene uses `table_round_A_small`, matching the named station and delivery target
path. Items staged `on_table` use its measured y=1.00 surface. `Lex01Interior` resolves stable
member IDs recursively inside each group and builds walk-blocking collision only for the prep
counter and two bar sections; chairs and small furniture remain non-solid as before.

## Gameplay and verification

Scenario objects still use `on_counter`, `in_fridge`, and `on_table`; only the small answer props
move between those authored stations. Group roots are built once with the room and persist across
scenario changes. Existing NPC, pickup, delivery, response, save, low-cost hover and legacy-world
paths remain in place.

For visual review, open `scenes/main.tscn` in Godot and press F6, then click the existing briefing button. Godot 4.7.1 movie capture crashed with signal 11 before producing images, so no screenshots are included; visual acceptance remains NOT_TESTED. The game starts at the south entrance; walk north to inspect the fixed areas. Controls: WASD, mouse look, E or left click to interact, Tab for the cursor, Enter to continue, H for translation, X to skip, F1 for help, Esc to pause.
