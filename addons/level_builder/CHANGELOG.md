# Changelog: Level Builder Lite

Lite is cut from the same source as the full version, so it inherits every fix
that lands there. Its version tracks the full pack's.

## 2.0.3 (2026-10-12)

The tabs show their names on Godot 4.5.

- **The Level Builder tab was blank on Godot 4.5.** Its tab beside the Inspector had no title, so
  "open the Level Builder tab" pointed at nothing. It is named when the pack switches on now. Godot
  4.7 was not affected.

## 2.0.2 (2026-09-28)

The re-roll buttons show their icon.

- **The re-roll buttons show a dice icon.** The editor's font has no emoji, so they were empty
  boxes.

## 2.0.1 (2026-09-27)

Every tab fits and scrolls, and new files show up by themselves.

- **Every tab fits and scrolls.** On smaller screens or at a bigger editor scale, the Generate tab
  ran off the bottom of the screen with no scroll bar, taking Check Level, Test Walk and the "Lock
  what you want kept" list with it. Each tab now scrolls on its own, Check Level and Test Walk stay
  at the bottom of every tab, and long labels wrap so the panel fits its default width, laptops
  included.
- **New presets and models show up by themselves.** A model added to a palette folder, or a preset,
  style or room type added to the generation folder, now appears when you open its tab or when the
  project's files change, with no Rescan. Rescan still works and keeps the category you were looking
  at, and Generate and Fill Selection always use the style and room type the dropdown shows.

## 2.0.0

- First release. Room scope: three room presets, all four style palettes, the
  zone overlay, per-room re-roll and Fill Selection.
- Setup, Layers, Colliders and Assets tabs complete and unrestricted.
- Check Level and Test Walk complete.
- The greybox starter set ships inside the addon, so everything works on a fresh
  install with no other assets.
- `demo/showcase_walk.tscn` is real output from the full version. Press F6 and
  walk a manor, a catacomb, a cloister and a region.
