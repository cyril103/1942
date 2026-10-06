# Cloud production and runtime

`build_clouds.py` creates four continuous density fields and bakes them with Blender 4.5.4 Cycles. `clouds-studio.blend` is the editable source and `cumulus-volume-bake.png` the production reference. Rebuild from the repository root with `tools/blender-4.5.4-windows-x64/blender.exe --background --python blender/clouds/build_clouds.py`.

The shipped images are the original refined atlas and the additional `game/assets/environment/clouds/cumulus-variety-atlas.png`. Both were generated with the built-in ImageGen tool. Exact prompts and provenance are in `CREDITS.md` and `VARIETY-CREDITS.md` alongside the textures. Rebuilding Blender does not overwrite these assets.

## Runtime

Eight reusable cloud cards and eight shadow cards. Eight silhouettes cycle per sector: small cumulus, dense large cumulus, elongated banks, open clusters and thin veils. Large banks reach about 19 world units wide versus 11 previously. Narrow viewports cap their size. Biome tint supplies warm dusk or cooler storm lighting. Veils have lighter opacity and shadows.

Clouds stay at -1.25 to -1.495, between terrain (-3.0) and cruising aircraft (0). Shadows are at -2.94. Depth testing preserves aircraft visibility above the clouds. Opacity stays constant during takeoff and recovery. Spawn placement reserves the complete curved carrier approach, with a bounded wind margin. Full card footprints are separated to avoid transparent overlap. Cards recycle only offscreen.

The shader uses two atlas samples (prelit RGBA and a density rim), while shadows use one blurred mip sample. Both atlases have mipmaps and alpha border fixing. No added shader fetches, ray marching, screen copies, dynamic lights or extra render targets. The visual volume is baked for the overhead camera; it is not a general-purpose volumetric renderer.

## Verification, 6 October 2026

`test_clouds.gd`: 5,150 checks pass, including ten minutes of scrolling, object reuse, carrier clearance, persistent opacity, all eight silhouettes, large-bank sizes, non-overlapping cloud cards, both mipmapped atlases and a rendered comparison confirming the aircraft fuselage stays above clouds. Screenshots cover five biomes.

`benchmark_clouds.gd`: GTX 1650, Compatibility, 1920x1080 window and 1920x972 flight viewport, VSync off. Frozen scene: 32 fighters, 96 enemy rounds, 24 player rounds, eight explosions, two escorts and one boss. Six visible cloud/shadow pairs deliberately overlap in this synthetic stress scene. ABBA order, 240 samples per block after warmup; root and flight GPU times are summed.

Mean GPU time: 2.165 ms without clouds, 2.294 ms with clouds, difference approximately 0.129 ms. Cloud scroll/animation CPU update: 0.030 ms. Draw calls: 676 to 688. Frame/block variation makes this an estimate of drawing cost, not a guarantee of unchanged gameplay FPS. Final measurements: `game/tests/cloud-performance-results.json`. The previous version's same-session baseline is preserved in `cloud-performance-before-variety.json`; its on/off difference was within measurement noise.

## References

- https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html
- https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html
- https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu
- https://docs.blender.org/manual/en/4.4/render/shader_nodes/shader/volume_principled.html

No third-party textures were downloaded.

The same 5,150 checks also pass against the exported Windows embedded pack using the Godot console engine (`--main-pack dist/PacificStrike/PacificStrike.exe` with the external test script). Direct release-executable test runs did not produce usable diagnostics and were stopped. Windows executable SHA256: `2F70D30BF37F141C14F7990CC323F21D0014E08F85E73740415BC1C22737C203`. Distribution ZIP rebuilt.
