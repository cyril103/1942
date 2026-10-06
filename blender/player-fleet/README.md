# Player fleet — 6 October 2026

The campaign now selects three distinct aircraft: the existing Vanguard, a Lockheed P-38 Lightning for Interceptor, and a Chance Vought F4U Corsair for Bulwark.

## Production assets

- Reference boards: `art/player-fleet/p38-reference.png` and `f4u-reference.png`, each with top, underside and front three-quarter views.
- Imagegen albedo atlases: `art/player-fleet/p38-albedo.png` and `f4u-albedo.png`. Four horizontal material strips, explicitly mapped with authored UVs. Prompts and generation method in `art/player-fleet/prompts.txt`.
- Editable, packed Blender scenes: `p38-studio.blend` and `f4u-studio.blend`. The generated reference board is packed as a non-rendering image object. Existing studio HDR retained.
- Rebuild script: `build_fleet.py`, run with Blender 4.5.4 in background mode. Generates GLBs, all six studio renders and the two transparent hangar portraits.
- GLBs with embedded textures: `game/assets/player-fleet/p38.glb` (5,906 triangles, 12 mesh groups) and `f4u.glb` (2,940 triangles, 9 mesh groups).
- Studio renders: `renders/player-fleet/{p38,f4u}-{top,underside,front}.png`.

These are stylized low-poly gameplay models, not engineering reconstructions. The P-38 has twin engine/tail booms, a short center nacelle and a connecting tailplane. The Corsair has actual inverted-gull wing geometry and a long radial-engine nose. Landing gear is retracted. Normals are recalculated; static surfaces are merged by material; propellers retain independent pivots. Materials use the generated base-color atlases with physically based metallic/roughness factors, not baked studio lighting. No separate normal-map claim is made.

## Gameplay

| Profile | Model | Speed | Salvos/s | Hull | Bombs |
|---|---|---:|---:|---:|---:|
| Vanguard | Existing player aircraft | 12 | 9.52 | 2 | 2 |
| Interceptor | P-38 Lightning | 14 | 11.11 | 2 | 2 |
| Bulwark | F4U Corsair | 10.4 | 8.33 | 3 | 3 |

Base values before upgrades. Wingspans are normalized to the existing gameplay size, preserving the established camera and collision fairness. Gun origins follow the central P-38 armament or Corsair wings; P-38 bullets smoothly widen over 60 ms to the Vanguard spacing, then remain parallel; the laser source follows the selected nose. The original saves already store the aircraft index and need no migration. The P-38's carrier operations are an intentional arcade game convention.

## Validation

`test_player_fleet.gd`: 50 checks covering all three profiles, actual imported model paths, rotating propeller pivots, gameplay values, screen bounds, muzzle origins, P-38 launch widening and stable separation, respawn and landing. GPU captures in `renders/player-fleet/game-*.png`. `game-detail-*` uses a temporary validation zoom; normal gameplay camera remains unchanged. Existing weapon and dynamic campaign regression tests also run.

## Shape references

- National Museum of the US Air Force: https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/196280/AFmuseum/lockheed-p-38l-lightning/
- National Naval Aviation Museum: https://navalaviationmuseum.org/f4u-1-corsair/nggallery/image/birdcage/
- National Air and Space Museum: https://airandspace.si.edu/collection-objects/vought-f4u-1d-corsair/nasm_A19610124000

Museum material was consulted for identification and silhouette; no museum images or third-party 3D meshes were copied into the game.

Final Windows package: the same 50 checks pass when loading the embedded exported game. Windows build and ZIP refreshed after the P-38 spacing adjustment.
