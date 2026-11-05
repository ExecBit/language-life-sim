# Level Builder Lite

Build walkable 3D levels in the Godot editor without the setup pain, for **Godot 4.5+**.
This is the free edition: **Room scope**.

## What's here, in full

- **Setup tab.** One click builds a lit, organised 3D scene: environment preset, sun with
  shadows, ground with collision, containers, and a PlayerSpawn.
- **Generate tab, Room scope.** Pick a room type, pick a style, press Generate. Rooms come out
  furnished around the thing they're for: circulation stays clear, furniture arrives in groups,
  and a style palette decides whether the place is swept or strewn with rubble. All four palettes
  are here, so is the zone overlay, so is per-room re-roll.
- **Fill Selection.** Build walls yourself, select them, and have the generator furnish inside
  them. It reads your geometry with physics and keeps your doorways clear.
- **Layers, Colliders, Assets tabs.** All of it, unrestricted.
- **Check Level and Test Walk.** All of it.
- The greybox starter set, so everything works before you own an asset pack.

## What the full version adds

- **Level scope.** A building. Rooms and corridors with aligned doorways, an entry yard, a walk
  from the front door to what you came for, and dead ends worth finding. Six presets.
- **World scope.** A region. Terrain, plots, roads, and a point of interest on every plot, with
  the buildings on them generated or left as markers you can move first.
- **Locks and re-planning.** Keep the rooms you like and have the rest re-plan around them.

## See what that looks like before you decide

Open `demo/showcase_walk.tscn` and press **F6**. That scene is real output from the full version:
a manor, a catacomb, a cloister and a walkable region, plus the same shrine under all four style
palettes. Walk around it. **F** flies.

## Install

1. Copy `addons/level_builder/` into your project's `addons/` folder.
2. Project Settings, Plugins, enable **Level Builder Lite**. The dock appears top right.
3. Setup tab: pick a preset, press **New 3D Level…**, save it.
4. Generate tab: pick a room and press **Generate**. Then press **Test Walk**.

MIT licensed. The greybox pieces are generated primitives. Use them anywhere, no credit needed.
