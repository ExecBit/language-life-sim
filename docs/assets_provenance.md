# Asset and source provenance (PREP-01)

Every third-party file this repository commits for Issue #4 is listed here with the exact upstream
commit it came from, its byte size and its SHA-256 as measured on the working tree. Re-check with:

```powershell
Get-ChildItem -Recurse -File assets/kaykit | Get-FileHash -Algorithm SHA256
```

(`Get-FileHash` has no `-Recurse` parameter; the file list has to be piped into it.) The command lists
109 files: the 68 third-party files in the tables below, the 3 textures Godot extracted from the
character GLBs (listed under the character table), and the 38 `*.import` sidecars Godot wrote during
import. Only the 68 downloaded files have hash rows here.

## Engine

- Godot `4.7.1.stable.official.a13da4feb` (installed locally through the WinGet package `GodotEngine.GodotEngine`).
- Used for: headless import, `scenes/prep_preview.tscn`, `scenes/prep_dialogue_smoke.tscn`.
- Official release page: https://godotengine.org/download/archive/4.7.1-stable/
- `project.godot` now also carries settings Godot wrote itself during import: `config/features` updated to `4.7`, and `animation/compatibility/default_parent_skeleton_in_mesh_instance_3d=true`, which the KayKit character import relies on.

## Dialogue plugin

- Dialogue Manager `v4.2.0` (release title "for Godot 4.7"), commit `bbf9d2a5f6a9eaa276310eea8b1379a936239d2e`.
- License: MIT — `addons/dialogue_manager/LICENSE` is kept with the copied source.
- Install method: the GitHub release publishes **no zip asset**, so the official tag archive `v4.2.0.tar.gz` (SHA-256 `a427116bff75029b4e3ee4d88b990f07133f242cc9a5ff4d483b2d17b88b7e55`) was downloaded into ignored `.local/downloads/` and `addons/dialogue_manager/` was copied out of it unchanged: 190 files, 726530 bytes.
- `project.godot` enables the plugin and declares the `DialogueManager` autoload by hand. `plugin.gd` would add that autoload with `add_autoload_singleton` when the editor enables the plugin; the entry is written explicitly so a headless run works without opening the editor.

## KayKit asset packs (CC0)

itch.io is the author's storefront, but its "Download Now" button routes through `/purchase` with "Name your own price" and therefore needs an itch.io account. The same packs are published by the author's own GitHub organisation `KayKit-Game-Assets` (linked from kaylousberg.com, and each repository's homepage points back to its itch.io page), already laid out as Godot `addons/` folders. Files were fetched from those pinned commits through `raw.githubusercontent.com`, and only the files listed below were taken — no archives, no whole packs, no FBX duplicates.

| Pack | itch.io page (reference) | Used source repo | Pinned commit |
| --- | --- | --- | --- |
| KayKit Adventurers 1.0 | https://kaylousberg.itch.io/kaykit-adventurers | `KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0` | `672074b73ba276876a19e8816ecdc5241817ab47` |
| KayKit Furniture Bits 1.0 | https://kaylousberg.itch.io/furniture-bits | `KayKit-Game-Assets/KayKit-Furniture-Bits-1.0` | `96d5930a8dbdb363409bbc2d3341718b00e17c9c` |
| KayKit Restaurant Bits 1.0 | https://kaylousberg.itch.io/restaurant-bits | `KayKit-Game-Assets/KayKit-Restaurant-Bits-1.0` | `153c8a7535b48237854cb54ff6890679f8c574d1` |

Each asset directory carries the pack's own `LICENSE.txt`, copied verbatim from the pinned commit. All three state the pack is CC0 ("No rights reserved. You can use it in commercial and non-commercial projects."), so redistribution of these committed files is allowed. CC0 does not require attribution, but the source is recorded above anyway.

Not used: KayKit Prototype Bits and the Kenney Food Kit (no fallback was needed), and the itch-only "KayKit Character Animations" pack — the character GLBs already ship `Idle`, `Walking_A/B/C`, `Interact` and `PickUp` on the same rig, so no separate animation pack and no retargeting was required.

### Characters — KayKit-Character-Pack-Adventures-1.0

| Committed file | Source path in the repo | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `assets/kaykit/characters/Knight.glb` | `addons/kaykit_character_pack_adventures/Characters/gltf/Knight.glb` | 3659532 | `60428e3abc09ba83e595d256e3af8c5c976b46cdae599f0802fc82b4a3445168` |
| `assets/kaykit/characters/Mage.glb` | `addons/kaykit_character_pack_adventures/Characters/gltf/Mage.glb` | 3589240 | `cf898585da33fab50c724d31605fb931eb2912e6d2280092141e98ca81ad507d` |
| `assets/kaykit/characters/Rogue_Hooded.glb` | `addons/kaykit_character_pack_adventures/Characters/gltf/Rogue_Hooded.glb` | 3597652 | `93e6e25213009952276d9cf34f5d96a243767334c66f280db0433ddfabb91545` |
| `assets/kaykit/characters/LICENSE.txt` | `LICENSE.txt` | 891 | `ae322141814056dda0deea7540d74c41d87aee1da319977cd1bd84ee5a923629` |

Each character GLB embeds its own texture and 76 animation clips, which is why the files are about 3.6 MB each. Subsetting the clips would need a custom glTF pipeline, which Issue #4 explicitly rules out.

`Rogue_Hooded.glb` was added by TAV-03 (Issue #10) as the guest character, from the same pinned commit as Knight and Mage and on the same shared rig, so its `Idle` and `Interact` clips work with the existing NPC code and no animation pack or retargeting is involved.

Godot's import also extracted the embedded textures into `Knight_knight_texture.png` (14172 bytes), `Mage_mage_texture.png` (16311 bytes) and `Rogue_Hooded_rogue_texture.png` (16670 bytes) next to the GLBs. Those three files, and every `*.import` sidecar in this repository, are generated by Godot 4.7.1 from the files above rather than downloaded — they carry no separate licence and are committed because Godot expects import metadata in version control.

### Furniture — KayKit-Furniture-Bits-1.0

| Committed file | Source path in the repo | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `assets/kaykit/furniture/table_medium.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/table_medium.gltf` | 2973 | `fd5e5fe8bbf1d3729b6bd725165d58490e9cbd8dd46ce42314b01f20951a302b` |
| `assets/kaykit/furniture/table_medium.bin` | `addons/kaykit_furniture_bits/Assets/gltf/table_medium.bin` | 9328 | `0e6ba8fd006f673d946979e45487067f4e274be9bbd07816fd371578d2a37518` |
| `assets/kaykit/furniture/cabinet_medium.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/cabinet_medium.gltf` | 3000 | `139419c479c6f8b38ac24e12ce85bf81a199e05067a544db879f7e403446c9dc` |
| `assets/kaykit/furniture/cabinet_medium.bin` | `addons/kaykit_furniture_bits/Assets/gltf/cabinet_medium.bin` | 23304 | `3fc4bff757a36226ecb9504dd6e9d031a5a6c957cb9cc2bb636f12ab49e877e6` |
| `assets/kaykit/furniture/couch.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/couch.gltf` | 3014 | `1a5b74b3a3368870783743c5ce7baa61f45f71131dca66af80b35fd4ac63c222` |
| `assets/kaykit/furniture/couch.bin` | `addons/kaykit_furniture_bits/Assets/gltf/couch.bin` | 21416 | `00f6c9892aa87e2894e049ba47d697307c158c5096eb41bdd44474d5e7ecf5e0` |
| `assets/kaykit/furniture/bed_single_A.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/bed_single_A.gltf` | 3009 | `7b2852bb66bf82cad3e0d03a499b1480879790fa66b645347e3e73761c4fe3f5` |
| `assets/kaykit/furniture/bed_single_A.bin` | `addons/kaykit_furniture_bits/Assets/gltf/bed_single_A.bin` | 22044 | `fc7631db4540d31cbe76dac3c672bc8836ee302796d14bba428bda84b9237f5b` |
| `assets/kaykit/furniture/pictureframe_medium.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/pictureframe_medium.gltf` | 3069 | `768ebf5e81d2d4dfe87276e70b7373ee541592ca409a57067e5e76626a010926` |
| `assets/kaykit/furniture/pictureframe_medium.bin` | `addons/kaykit_furniture_bits/Assets/gltf/pictureframe_medium.bin` | 3176 | `ae120086448ad5f8c8a2e1a360355f9052f4b7848e5b422b00398827b9355e8d` |
| `assets/kaykit/furniture/furniturebits_texture.png` | `addons/kaykit_furniture_bits/Assets/gltf/furniturebits_texture.png` | 15605 | `de62db37a80d1801c3d9eb674890ae04b04469e0c149481a51fa250562c628dc` |
| `assets/kaykit/furniture/LICENSE.txt` | `LICENSE.txt` | 827 | `cd675f2adc31eb5fedaedc1072d8ddc27b917f523682f0561837c03dc56393cb` |

The five props were chosen so each one matches a lemma in `data/vocabulary/de_a1_starter.json`: table_medium = *der Tisch*, cabinet_medium = *der Schrank*, couch = *das Sofa*, bed_single_A = *das Bett*, pictureframe_medium = *das Bild*. `furniturebits_texture.png` is the single shared atlas these `.gltf` files reference.

#### Measured prop sizes behind scenario `s14`

Scenario `s14` asks a comparison between two of these props, so the answer rests on the imported geometry instead of on a size judgement. `tools/prep_probe.gd` merges the world-space AABB of each prop's meshes once per run, prints them and asserts the comparison:

| Prop | Printed size (x, y, z in metres) |
| --- | --- |
| `couch.gltf` (*das Sofa*) | `PROP_SIZE Couch size=(3.000, 1.224, 1.600)` |
| `pictureframe_medium.gltf` (*das Bild*) | `PROP_SIZE PictureframeMedium size=(0.700, 0.900, 0.200)` |

`SIZE_CHECK Couch > PictureframeMedium = true` is part of the same headless preview run, and the numbers are quoted in `s14`'s `scene_state.size_evidence`.

### Items — KayKit-Restaurant-Bits-1.0

| Committed file | Source path in the repo | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `assets/kaykit/items/fridge_A.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/fridge_A.gltf` | 7062 | `a1835597180f9636dd23669900c1f07fd38813fc5a50685e1d4a7ac1b988ae62` |
| `assets/kaykit/items/fridge_A.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/fridge_A.bin` | 26980 | `58448d94b0c4799586344b2802fdb2c83dbdd80a350778621b0da096c7c77459` |
| `assets/kaykit/items/food_ingredient_bun.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_bun.gltf` | 3071 | `d535883d1395208132a441a264c6bb91f0fb045a4a2bac613ba599fca7ca7c06` |
| `assets/kaykit/items/food_ingredient_bun.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_bun.bin` | 15632 | `a49d342c9dad3f2318798f7dddd72298ea3d364cc76a6440efacd46ffb473fe8` |
| `assets/kaykit/items/food_ingredient_potato.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_potato.gltf` | 3064 | `978e456df24110a4ac9f7469bd24a9e65ecc5a312a0475e34cb2567ce19d8f40` |
| `assets/kaykit/items/food_ingredient_potato.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_potato.bin` | 3496 | `905ad1d4c25e9b6a4b4eb20c994f485cd3a48f72cb1ce94a34fe37ccb49dc182` |
| `assets/kaykit/items/food_ingredient_tomato.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_tomato.gltf` | 3082 | `563c960cbc6a7a0580a75e24e964cab4426fdeda90f602912e57be2fe568c90d` |
| `assets/kaykit/items/food_ingredient_tomato.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_tomato.bin` | 13304 | `82a2319e73119c1dbb9e35eb357b205936bf6f185b9bbf1bf66b5025109925b2` |
| `assets/kaykit/items/food_ingredient_steak.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_steak.gltf` | 3077 | `651a04027439cb47c814db3b943cc28f10f7093e74695214ba86441d212873f3` |
| `assets/kaykit/items/food_ingredient_steak.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/food_ingredient_steak.bin` | 13440 | `6196cd9e50e6c2db8fdf0472f0cf031245e898cc4fe98424cfad8b207cedb717` |
| `assets/kaykit/items/restaurantbits_texture.png` | `addons/kaykit_restaurant_bits/Assets/gltf/restaurantbits_texture.png` | 21070 | `1bfff8f880c5e5e1b793bc46fa1f91149b7f70766174a817b3d5962495c5e40f` |
| `assets/kaykit/items/LICENSE.txt` | `LICENSE.txt` | 862 | `4da4ad3a3face68a71c11c8adc8e93017fdeb8fd67fcb0ca8286bd9c3dbbf674` |

Item choice follows the same rule: fridge_A = *der Kühlschrank*, food_ingredient_bun = *das Brötchen*, food_ingredient_potato = *die Kartoffel*, food_ingredient_tomato = *die Tomate*, food_ingredient_steak = *das Fleisch*.

### Tavern room — TAV-03 (Issue #10)

The tavern is built from the two Bit packs already pinned above. No new pack, texture or licence was needed: the `.gltf` files reference the same `restaurantbits_texture.png` and `furniturebits_texture.png` atlases PREP-01 committed, so each room model added 41 files totalling 3 889 965 bytes for the whole room, of which 3 597 652 bytes is the character GLB.

| Committed file | Source path in the repo | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `assets/kaykit/items/wall.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/wall.gltf` | 2983 | `f50162af946c236fce27f3f561d9d4ab01b0f31fd033a4694f2969e34b992f42` |
| `assets/kaykit/items/wall.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/wall.bin` | 5320 | `7bb2ea4be9038077a77d1ef2295c292072b9e5bf1815c11b11c33c0c6fc9940c` |
| `assets/kaykit/items/wall_doorway.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/wall_doorway.gltf` | 3000 | `85e91a96f9a010bd0680342453a16ee1d94f1dfa7858d4cd99f5047cd01a74c6` |
| `assets/kaykit/items/wall_doorway.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/wall_doorway.bin` | 10316 | `8190f781ad58e006d1ddfdf065476302e2004765b0b351e001d782a6adfed060` |
| `assets/kaykit/items/wall_window_open.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/wall_window_open.gltf` | 3010 | `2c1e209505ca0d7538a369a2ef00d39c5095cb7ca31a04ddc4a9504e355e4d66` |
| `assets/kaykit/items/wall_window_open.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/wall_window_open.bin` | 11392 | `2e2712c4761cb20de81bac2b6c7bac4cbfd4da2c00beb28427898c40b3f6b682` |
| `assets/kaykit/items/wall_orderwindow.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/wall_orderwindow.gltf` | 3026 | `8513b09ef5e24ef63c52bd831ae53bd4bcef5c93ee8d5d73fd10431f8f17abeb` |
| `assets/kaykit/items/wall_orderwindow.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/wall_orderwindow.bin` | 12116 | `08a03caa05d8aba4a601a3e6077eac04931df4c1f093b0ed8fd431b3836a18d2` |
| `assets/kaykit/items/door_A.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/door_A.gltf` | 3026 | `5bcfe533544343c0dc6e32ce96ee727b2525ca76233c2db560961bc733d78cdc` |
| `assets/kaykit/items/door_A.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/door_A.bin` | 11752 | `7db6f8465a5851c7cc38c1c41cf5845a652624f46118e2533847585d06c275b5` |
| `assets/kaykit/items/kitchencounter_straight_A.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/kitchencounter_straight_A.gltf` | 2989 | `500afffa4c87a579a046b67f10c8b2b7907a3dd0983544643c581b95153d6008` |
| `assets/kaykit/items/kitchencounter_straight_A.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/kitchencounter_straight_A.bin` | 8400 | `78e3e82538faf0f03d0799b7980f006f1fe7a45ab7c64ae401d66dee576ebb19` |
| `assets/kaykit/items/kitchencabinet.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/kitchencabinet.gltf` | 2965 | `73969db052be1f37717012874f43c2dace7e011bf9b59179d8e0d3a40f5c24c1` |
| `assets/kaykit/items/kitchencabinet.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/kitchencabinet.bin` | 7400 | `a25d0ba886e4bf558ea4afc636f1b62cbd0e45ee4c6a7cc3e488022f98dfc136` |
| `assets/kaykit/items/stove_single.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/stove_single.gltf` | 3008 | `cce0730ec2025399a68cb6afaa8acb2f54fcb3d70537a26f62564f6f7754f679` |
| `assets/kaykit/items/stove_single.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/stove_single.bin` | 36368 | `a388f9f1668f7deec37dedf9b45113e593a4f0876d25454d9c22decd0edbaf28` |
| `assets/kaykit/items/pillar_A.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/pillar_A.gltf` | 3022 | `8995e350d2f1af56d3007287bcd1782b27ce3be7e2188414aca73d1be14bb7ba` |
| `assets/kaykit/items/pillar_A.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/pillar_A.bin` | 3080 | `58b2598af50e06eedbddb3b74d9363b5af5ed2d13437619f31bb9b25e55840b5` |
| `assets/kaykit/items/crate.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/crate.gltf` | 3017 | `f745014f6239147f2528ac24ef988a5833d048bd3aede81085f4c4fc879a8e16` |
| `assets/kaykit/items/crate.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/crate.bin` | 8984 | `252687039209b62a3283319d2836d0e0d6745dd638ea53e2315df981c75a6c07` |
| `assets/kaykit/items/crate_potatoes.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/crate_potatoes.gltf` | 3040 | `4d04acf2bfebdee4d1f3585cf7e0507d50c61b729c255231271416171af564f5` |
| `assets/kaykit/items/crate_potatoes.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/crate_potatoes.bin` | 29960 | `0f77c9bdef536155f586907f3d100d373c8a62a7a017f032e5e623e604794996` |
| `assets/kaykit/items/table_round_A.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/table_round_A.gltf` | 3001 | `20a3b1b8d1cf6cad642f3f9590667bb9b7fa3c318dd603604280a3254be5cf33` |
| `assets/kaykit/items/table_round_A.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/table_round_A.bin` | 12528 | `d6122d1b2b5c5b7348f033b97e6cac7f897dd0978a4b7a9c383d2f15a02a5844` |
| `assets/kaykit/items/table_round_A_small.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/table_round_A_small.gltf` | 3017 | `eba53971817c536c8df8b69dd41e1f320cf16c450a2f3141ac92bc0eb5213996` |
| `assets/kaykit/items/table_round_A_small.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/table_round_A_small.bin` | 12528 | `8f39b021b1153eb22653a20103e3308bcc8fb7d3c53439c53d6f0e20331f51c4` |
| `assets/kaykit/items/chair_A.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/chair_A.gltf` | 3037 | `0d0abdc382abedb3e4bc2e0260af663c16ff2dab0d441f09d675e0709a7a7310` |
| `assets/kaykit/items/chair_A.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/chair_A.bin` | 16872 | `c95a15bc30e2bb9f122762590819c99934db31b7e7dbf3e54b68eb105e36148b` |
| `assets/kaykit/items/chair_stool.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/chair_stool.gltf` | 3009 | `6b224ab4884e7fff7083c02f630afc63cad698dbd4a99860d6f8988f308069b6` |
| `assets/kaykit/items/chair_stool.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/chair_stool.bin` | 10016 | `dc5b44cad6aece8dc5c6de343f76ff6d600a8bf3c24da27dc44e62a583176325` |
| `assets/kaykit/items/pot_A.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/pot_A.gltf` | 2977 | `3dc03eff7a73860aa61f41d49d118811c75ca74113ce49f27446a8f99040df1c` |
| `assets/kaykit/items/pot_A.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/pot_A.bin` | 13016 | `1a60075faf796fae6897bb4c97e09d326bb755a6d16369658994332cc582404d` |
| `assets/kaykit/items/menu.gltf` | `addons/kaykit_restaurant_bits/Assets/gltf/menu.gltf` | 2990 | `8f71400aa63c18c893dc85144e5ea5fa4f152525510548d68e0f6f5f5d3966fb` |
| `assets/kaykit/items/menu.bin` | `addons/kaykit_restaurant_bits/Assets/gltf/menu.bin` | 5448 | `56bee60b3e949e829f4801d9c01dae2706d9a3f36d326b336881c9ec21cc5650` |
| `assets/kaykit/furniture/lamp_standing.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/lamp_standing.gltf` | 3034 | `ff42a083e688c94948493c441d4db51c7e0736336525b3eed4f4da75825b88b7` |
| `assets/kaykit/furniture/lamp_standing.bin` | `addons/kaykit_furniture_bits/Assets/gltf/lamp_standing.bin` | 11648 | `ee58a9e2776406071c8ac60714f1b4dd7ad83a11848ee24aec77b297c9d535d9` |
| `assets/kaykit/furniture/rug_rectangle_A.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/rug_rectangle_A.gltf` | 2971 | `892417306a01eac711c6af97b148fc152d375940ec3660964b36e10ea2a8cfda` |
| `assets/kaykit/furniture/rug_rectangle_A.bin` | `addons/kaykit_furniture_bits/Assets/gltf/rug_rectangle_A.bin` | 1800 | `10eb71fc2b20b056b6186526d451ee0a560c425495402d7818f4413795aba506` |
| `assets/kaykit/furniture/pictureframe_large_A.gltf` | `addons/kaykit_furniture_bits/Assets/gltf/pictureframe_large_A.gltf` | 3071 | `b12aadc4e0179aa9c27a18cd31f5a980159188a20d11cc62b9c5a97e4381c59f` |
| `assets/kaykit/furniture/pictureframe_large_A.bin` | `addons/kaykit_furniture_bits/Assets/gltf/pictureframe_large_A.bin` | 3176 | `85368442c0af0cc12cd32fa512284391905219dd7a88e3360d69a1a25db2262c` |

None of these is a lemma prop: not one of them is referenced by `scene_object` in `data/vocabulary/de_a1_starter.json`, and none is used as an option model or as an anchor by the scenario files, so a room model can never be mistaken for an answer. Sizes below are the first `VEC3` accessor bounds printed by the pinned `.gltf` files themselves, which is what the layout rules in `data/room/lex01_room.json` are measured against.

| Model | Footprint (x, z in metres) | Height (y) |
| --- | --- | --- |
| `wall.gltf` | 4.00 x 0.50 | 0.00 … 4.00 |
| `kitchencounter_straight_A.gltf` | 2.00 x 1.00 (4.00 x 1.00 turned 90° into a bar run) | 0.00 … 1.00 |
| `crate.gltf` / `crate_potatoes.gltf` | 2.00 x 2.00 | 0.00 … 0.80 |
| `table_round_A.gltf` | 3.00 x 3.00 | 0.00 … 1.00 |
| `table_round_A_small.gltf` | 1.50 x 1.50 | 0.00 … 0.90 |
| `chair_A.gltf` | 1.10 x 1.20 | 0.00 … 1.21 |
| `stove_single.gltf` | 1.20 x 1.00 | 0.00 … 1.21 |
| `kitchencabinet.gltf` | 2.00 x 0.60 | 2.00 … 4.00 (a wall unit, kept hanging) |

Not taken from these packs, although the packs contain them: `glass`, `mug`, `cup`, `bottle`, `tray`, `cash`, `register` and `bill`. `docs/tav01_learning_plan.md` records why their absence keeps two planned shift events unbuildable.

## Vocabulary source

- Goethe-Zertifikat A1 "Start Deutsch 1" Wortliste, section *Alphabetische Wortliste*.
- The page named in Issue #4 (https://www.goethe.de/ins/se/de/m/spr/prf/ueb/pa1.html) answers `HTTP 403` to scripted clients; the official PDF behind it was downloaded instead: https://www.goethe.de/pro/relaunch/prf/de/A1_SD1_Wortliste_02.pdf
- Downloaded copy (kept in ignored `.local/downloads/`, not committed): 712341 bytes, SHA-256 `45fb648bc0ac02338f7898cae065953e320ab72ed0c14e13e0deffe6f1c5d64e`, 29 pages.
- Every lemma in `data/vocabulary/de_a1_starter.json` records the printed entry, the PDF page and the source's own example sentence. The file now holds **47 lemmas**: the 15 PREP-01 delivered (unchanged ids, values and order) plus 32 added by TAV-01 (Issue #8) for the tavern curriculum - 12 verbs, 7 adjectives, 2 prepositions, 1 adverb, 2 expressions and 13 nouns.
- `source_kind` records *how* the source printed the word: `headword`, or `nebeneintrag` / `redewendung` for a word the list prints indented under a headword, in which case `source_parent` names that headword. Only two lemmas are of the second kind: *danke* (page 13, under *danken*) and *„Wie bitte?“* (page 26, under *wie*). No lemma claims to be a headword that the source did not print as one.
- `checked_but_absent` lists everyday words that were looked for and are **not** entries in the A1 list, which is why props such as a chair (*der Stuhl*), a plate (*der Teller*), a bar (*die Theke*), a waiter (*der Kellner*) or a warm/hot/fresh/empty/full adjective are not committed. Near matches are named instead of counted as the same word: *hinten* (17) is an entry, *hinter* is not; *der Herd* (15) appears only inside *die Küche*'s example sentence.
- `reserve_pool` holds 13 further A1 entries verified on a page but deliberately **not** committed as lemmas, each with the reason it is held back (*kaputt, der Preis, die Flasche, das Essen, das Frühstück, mögen, die Karte, bitte, die Entschuldigung, der Moment, „Einen Moment bitte“, Guten Tag, das Restaurant, hinten*). They are a claim about the source, not about the curriculum: none of them is taught until a later task commits it as a lemma.
- The list is a candidate A1 set chosen for a tavern shift, **not** a frequency ranking, and not „the most frequent German words“.
- English and Russian glosses are agent-authored helper translations; the Goethe list itself is monolingual. CI now requires a Cyrillic Russian meaning for **every** lemma, not only for the nouns that have a prop model, because a verb, an adverb or an expression has no object to point at and the hint text is the only place its meaning exists. The glosses still need human review before they can be trusted as teaching.
- Extraction used a throwaway `.local/venv` with `pypdf`; no PDF tooling is committed. TAV-01 re-extracted the same PDF with `extraction_mode="layout"` because the plain pass collapses several pages into one line and therefore cannot show the difference between a headword and an indented *Nebeneintrag*. That re-extraction corrected two pre-existing records rather than loosening the check: *das Brötchen* is printed with an en dash („das Brötchen, –“, and a lone dash in this list marks a plural equal to the lemma) and the Kühlschrank example uses an en dash after the question mark. The 16 absence claims and the 13 reserve entries were re-checked the same way; see `docs/tav01_learning_plan.md`.

## Dialogue plugin smoke

The two-choice reply is proven with the plugin's own balloon, not a custom UI: `tools/prep_dialogue_probe.gd` calls `DialogueManager.show_dialogue_balloon(...)`, asserts the balloon is visible with the German line in its `DialogueLabel` and exactly two visible answer buttons from `ResponsesMenu.get_menu_items()`, then clicks the second button with a real `InputEventMouseButton` pushed through `get_viewport().push_input(...)` and asserts the balloon advanced to the matching branch before `dialogue_ended` fired. That run needs a window (GUI picking is not reliable headless), so it is a short windowed smoke test:

```powershell
& $godot --path . res://scenes/prep_dialogue_smoke.tscn --quit-after 1500 -- --auto
```

Running the same scene without `-- --auto` leaves the balloon open for a human to click.

## Scenario content

Three authored files, 27 records in total, all written for this project and taken from no source, so no third-party licence applies to them:

- `data/scenarios/lex01_starter.json` - 15 records (PREP-01).
- `data/scenarios/lex01_extension.json` - 2 records (LEX-01 delayed retrieval).
- `data/scenarios/tav01_sample_shift.json` - 10 records `t01`...`t10` (TAV-01, Issue #8): six day-1 records that introduce the new corpus words *holen, nehmen, zusammen, kosten, billig, teuer, fertig*, and four day-2 records that revisit four of them in the other camera framing with the staged facts changed. They are a representative subset, not the whole shift: the plan in `docs/tav01_learning_plan.md` records which events and which lemmas wait for TAV-03 props or TAV-04 event situations, and why.

Rules in those files are asserted by CI rather than left to the reader:

- `distractor_note` - `distractor_lemma_ids` is the lemmas of the incorrect options minus the lemmas of the correct option; an empty list is valid (s13's and t03's two answers differ only by *ja*/*nein*).
- `presentation_note` - option ids are the authored display slots, the correct answers are spread over `a`/`b`/`c` (starter 5/6/4, extension 1/1, sample shift 5/4/1, so 11/11/5 across all 27 records), and LEX-01 must shuffle the visible order at play time so a fixed position can never become the strategy.
- `gloss_note` - every record carries `utterance_gloss_ru` and every `respond` option carries `gloss_ru`, because the translation button has nothing to show otherwise.
- `guided_note` - exactly one first-day `find_select` record carries `guided: true`; that record is the teach-before-test example and is presented first on day 1.
- `decidability_note` (tav01 file) - a corpus lemma becomes a target only when the player has to understand it to answer (a word that the answer does not depend on would be credited by `Lex01Progress.attempt()` as practice that never happened), and only when the answer follows from facts the record presents: staged positions (t01, t03, t05, t07, t09, t10), a price stated in the utterance itself (t04, t06, t08), or object identity, which is the basis the committed `bring_deliver` records already use (t02). `deferred_lemma_note` records the lemmas that are *not* targets here and the single thing each one waits for, so a new word is never taught as a guess.

## Interface language and the Cyrillic font

The first human test of LEX-01 (PR #6 review) could not start, because every instruction and control was German while German was the unknown language. The slice now separates the two jobs: **German is the content being learned** (the NPC sentence, the answer sentences and the correct-answer feedback, all from `data/scenarios`), and **Russian is the language that operates the game** (instructions, buttons, status lines, onboarding and summary labels, all from `data/ui/lex01_ui_ru.json`). No gameplay script contains an interface string in either language, and CI asserts that the three gameplay scripts contain neither Cyrillic nor a hard-coded German instruction, so rewording or rebranding the interface is a data change.

That only works if Godot can draw Cyrillic, which was measured instead of assumed:

- `ThemeDB.fallback_font` in Godot 4.7.1 is a built-in `FontFile` (no `res://` path) and reports `has_char` `true` for all 64 probed Cyrillic code points, so **no font asset is committed** and `project.godot` has no `gui/theme/custom_font`.
- The measurement was checked against a control: the same font reports `has_char` `false` for 8 Devanagari and 4 CJK code points, which is what makes the Cyrillic result a real coverage signal rather than a method that always answers yes.
- `tools/lex01_probe.gd` keeps that guard alive: it re-probes the active font for the whole Cyrillic alphabet every run and asserts the labels the player clicks really carry Cyrillic, so a future font or theme change that loses Cyrillic fails the probe instead of silently rendering empty boxes.

This section adds no third-party file; the 68 rows above are still the only third-party files this repository commits.

## Not committed

`.local/` holds the Dialogue Manager archive, the Goethe PDF, the extracted text, the scratch fetch and extraction scripts, the throwaway venv and all Godot run logs; `.godot/` holds import caches. The 68 rows above are the only third-party files this repository commits.
