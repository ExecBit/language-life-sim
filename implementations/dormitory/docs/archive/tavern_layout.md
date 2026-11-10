# Tavern scene

`scenes/tavern.tscn` is the tavern's spatial source of truth. Open it in Godot to see the full
three-room layout before running the game. `scenes/main.tscn` instances it alongside the player
and HUD.

The authored scene preserves the LAY-05 B connected hall, kitchen and storeroom, furniture,
doorways, lighting, collision, NPCs, and spawn markers. Furniture nodes have readable names and
editable transforms. Gameplay stations keep stable IDs such as `guest_table_1`, `service_counter`
and `kitchen_fridge`; scenario props use those scene nodes as placement and delivery anchors.

`data/room/lex01_room.json` holds player controls, scenario placement modes, and small-item
placement metadata. It does not contain static location transforms. The older LEX-01 practice
scenarios remain available as regression content; their candidate positions and context settings
are gameplay data, while the tavern itself always comes from the authored scene.
