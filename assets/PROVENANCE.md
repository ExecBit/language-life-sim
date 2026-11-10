# Asset provenance

The old KayKit tavern, vocabulary and Dialogue Manager have been removed from the current tree. Their previous attribution and file hashes remain in Git history.

## Cogito and plugins

The dependency snapshot comes from the local Cogito repository commit `533e773e`, origin https://codeberg.org/Phazorknight/Cogito. Cogito stays under `addons/cogito/`; its root MIT license is preserved there. Bundled third-party notices (including fonts and prototype textures) remain with their assets. Project gameplay code is kept separately under `implementations/dormitory/game/`.

Other dependency directories are `godot_state_charts`, `input_helper`, `quick_audio`, `mtoon`, and `vrm` (plugin version 2.5.9, AzPepoze fork of V-Sekai). Existing plugin license notices are preserved. The missing MIT notice for VRM was restored from https://github.com/AzPepoze/godot-vrm/blob/dev/LICENSE (blob 08e0e1772276b1853bbc8b804be6d32abebb3f36); Montserrat copyright is preserved from the bundled font name table (2011 The Montserrat Project Authors); the OFL license text was restored from https://github.com/google/fonts/blob/main/ofl/montserrat/OFL.txt (blob fe576a2ee1f96353b05d030c0b7620d525cc53a8). VRM native libraries are required for the existing importer/physics integration. Dependency license completeness must be reviewed before distributing an exported game; this migration makes no blanket claim that Cogito's MIT license covers every bundled asset.

## VRM characters

- `assets/characters/fallback.vrm` and `implementations/dormitory/game/shop/Assets/fallback_vendor.vrm`: VRoid Project AvatarSample_C. Embedded license URLs allow everyone, commercial use, modification and redistribution, without required credit. Original metadata remains embedded.
- Local-only `assets/characters/private/astera.vrm`: wondrous21, Astera. Embedded metadata: `OnlyAuthor`, `commercialUssageName: Disallow`, `licenseName: Redistribution_Prohibited`. Copied locally from the user's existing Cogito project; the entire private directory is ignored. No Astera source or import settings may be committed. The included sample is used when Astera is absent.
- The proposed BOOTH seller is not part of this migration. No restricted BOOTH model is included.

## Motifect animations

`assets/animations/motifect/` contains the Daily Life, Emotes & Social, and Locomotion packs. Their original README notices are retained beside the FBX files: free use in personal/commercial games and interactive projects; no redistribution/resale of raw animations as a standalone product. The clips are included as game resources, not sold as an animation pack. Sources: https://motifect.itch.io/motifect-daily-life-motion-pack, https://motifect.itch.io/motifect-emotes-social-motion-pack, and https://motifect.itch.io/motifect-locomotion-motion-pack.

The MVP's standing idle and prologue walk use `idle_neutral` and `walk_forward` from Motifect Locomotion through the shared retarget adapter. Quaternius's bundled library remains inside the Cogito dependency, but the MVP no longer references it for character animation.

House/shop geometry and SVG item icons are existing project-authored prototype resources. Cache files, downloads, logs and the old local prototype backup are not versioned.
