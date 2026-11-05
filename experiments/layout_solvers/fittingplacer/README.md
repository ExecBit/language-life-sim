# FittingPlacer evaluation (LAY-01 / Issue #24)

## Decision: NO-GO for the tavern proof

FittingPlacer is a real **constraint-based local furniture fitter**, not a random coordinate scatterer. It can attach typed furniture faces at specified distances, attach a selected face to a wall, and search a discretized room grid while rejecting overlaps and authored clearance areas. Its room model also reserves the immediate opening area of doors and windows.

It does **not** represent or validate walkable routes, reachability, or connectivity from a door to a set of stations. Source inspection found no path/route/connectivity representation or check in `Main/Room.cs`, `Main/Furnisher.cs`, or `Main/PlacementUnit.cs`. `Room` checks candidate placements against local obstruction/clearance grid cells; `Furnisher.TestPlacementRecursive` only searches placements for non-overlap. Door clearance is local to the door. A successful fit therefore cannot establish the required entrance-to-bar, dining, and kitchen paths.

That missing hard requirement is the stop condition in Issue #24 and Epic #23. Adding a route planner, post-placement route validator that regenerates placements, or hand-authored corridor obstruction would exceed the approved evaluation and would mask the capability gap. No Godot bridge, generated tavern JSON, or screenshots were produced after reaching this gate; the mandatory visual tavern proof is **NOT TESTED**.

## What was verified

| Check | Result | Evidence |
| --- | --- | --- |
| Upstream availability | PASS | Public C# repository, last upstream code push 2018-06-20; current repository metadata showed updated 2026-07-07. |
| License | PASS | Dual licensed in upstream `README.md`: MIT (`LICENSE.txt`) or CC0 (`LICENSE-Alternative.txt`). Upstream source is not copied into this experiment. |
| Build/run as supplied | FAIL | Upstream projects target .NET Framework 4.6; `dotnet build` failed because the .NET Framework 4.6 reference assemblies are not installed. |
| Upstream algorithm execution | PASS | The unchanged upstream `Main/*.cs` sources compiled into a temporary .NET 9 harness and ran the upstream console example with its original `FittingDatabase.xml` and seed 4242. Output: `requested=8 placed=8`, followed by 8 model positions/orientations. Temporary harness, clone, and output are in ignored `.local/`. |
| Side alignment and clearance | PASS (code-supported) | Upstream `FittingDatabase.xml` defines typed face relations and per-model clearance; `Furnisher.GenerateFittingLayout` connects related faces and `PlacementUnit.TryFitAt` checks obstruction/clearance grid occupancy. |
| Wall attachment | PASS (code-supported) | `Furnisher` recognizes the built-in `wall` face type and registers wall constraints for a selected fitting face. |
| Entrance path to required stations | FAIL | No route/reachability constraint or validation exists. Door opening clearance only reserves cells at the door. |
| KayKit/Godot visualization | NOT TESTED | Not reached because the solver fails the route requirement. Godot 4.7.1 and the existing KayKit assets are available in the host project, but no furniture layout was generated for them. |

## Manual work and limits

The user must author a semantic XML database mapping each model to dimensions, face types, pairwise side relations, and clearance areas, then choose which model IDs enter the room. The solver chooses placements for those constraints. A wall relation is available, but only one wall relation is selected per fitting during a generation. The algorithm randomizes valid placement domains; a seed can make a run repeatable. It does not infer tavern semantics from meshes, select design zones, understand service/customer sides unless encoded as faces, or guarantee a usable route.

The stock example is a capability smoke test, not the required tavern layout. No placement values are being claimed as a tavern proof.

## Reproduction

The original implementation was fetched into ignored `.local/FittingPlacer` at upstream `master` commit `1cdb703197b41d418e7ce686e74c7aad835ddb37`. The upstream console sample is `RunApplication/FittingPlacerRunApplication.cs`. Its stock project targets .NET Framework 4.6 and cannot build in the tested environment without that targeting pack. To execute the unchanged library sources with the available .NET 9 SDK, a temporary console harness compiled `.local/FittingPlacer/Main/*.cs` directly and invoked the same sample room, model IDs, and database from `RunApplication/FittingPlacerRunApplication.cs`, with seed 4242. The temporary harness and full console output remain under ignored `.local/runner/`.

Upstream links: [FittingPlacer](https://github.com/david-dot/FittingPlacer), [FittingPlacer for Unity](https://github.com/david-dot/FittingPlacerForUnity), [KayKit Furniture Bits license](../../../assets/kaykit/furniture/LICENSE.txt), [KayKit Restaurant Bits license](../../../assets/kaykit/items/LICENSE.txt).

## Reproduction and status summary

- PASS: unchanged upstream algorithm executed on its stock console input; 8/8 placements returned.
- FAIL: no global path/reachability constraint, so it cannot meet the required functional arrangement gate by itself.
- NOT_TESTED: isolated Godot scene, JSON furniture layout, top-down screenshot, first-person screenshots, visual walkability.
- No files in the live game or PR #16/#22 were modified.

Closes #24
