# Abandoned mine bedrock kit

These twelve original project meshes are created in Blender by `build_rock_kit.py`. They do not contain third-party scan/model data. The playable cave uses them for irregular wall relief, fallen stone at wall feet, and shore gravel. Runtime stone shading comes from `cave_art_direction.gd.geological_material(false)`, shared with the bedrock, rather than the soil material.

## Source and output

- Reproducible source: `asset-staging/blender_abandoned_mine/art_direction/build_rock_kit.py`
- Editable Blender file: `asset-staging/blender_abandoned_mine/art_direction/art_rock_kit.blend`
- Shape inspection render: `asset-staging/blender_abandoned_mine/art_direction/rock_kit_inspection.png`
- Measured mesh inventory: `asset-staging/blender_abandoned_mine/art_direction/rock_kit_manifest.json`
- Game asset: `godot-game/assets/3d/abandoned_mine/art_rock_kit.glb`
- Real placement code: `godot-game/scripts/cave_art_details.gd`

The `.blend` spaces the twelve stones apart for editing. The GLB exports each stone at the origin with identity transforms. Blender x/y/z becomes Godot x/−z/y. Every exported mesh spans Godot x/z approximately −0.5 to 0.5 and y 0 to 1; float32 export differences are below 0.000001m.

## Geometry

Each seed begins with an independently rotated solid, then receives oblique fracture cuts, two-segment edge wear, surface subdivision, three scales of erosion, and simplification. A fresh planar bottom is cut and capped after simplification, ensuring actual supporting vertices survive. The final result remains a closed solid; it does not use open sheets, floating decals, or an icosphere.

The generator checks that every final edge has two adjacent faces, including a separate coordinate-based audit after welding, and that each flat base contains at least three vertices. Rare invalid bevel slivers cause that seed to be rejected and regenerated deterministically. Final triangle counts for variants `ErodedBedrock_00` through `11` are **780, 904, 742, 704, 696, 724, 832, 766, 834, 770, 752, and 874**. The generator's manifest records the real base vertices and accepted deterministic seed of each variant.

## Rebuild

From the project root, run without opening Blender's interface:

```sh
/usr/sbin/taskpolicy -b /usr/bin/nice -n 10 \
  /Applications/Blender.app/Contents/MacOS/Blender \
  --background --threads 2 --python-exit-code 1 \
  --python asset-staging/blender_abandoned_mine/art_direction/build_rock_kit.py
```

Reimport the new GLB in Godot before running the placement test:

```sh
godot-game/tests/run_headless_tests.sh cave_art_details
```

## Contact and visibility checks

Runtime placement uses actual imported `Collision_Terrain_*` triangle rays. The raster height field only supplies a ray starting height. Floor placement tests the actual planar base's extremal vertices in twelve directions. Wall placement uses up to sixteen actual rear vertices across the complete back area, embeds those points into the wall, and limits exposed depth. Every transformed mesh's full horizontal extent keeps a 1.35m margin from authored route centre lines; no new colliders obstruct the player. Ground fragments are rejected near gameplay positions and mine props.

`get_state_snapshot()` exposes real contact points and placement counts. `get_render_batches()` returns copies of the exact transforms submitted to each MultiMesh. The headless dummy renderer cannot return stored MultiMesh transforms, so the physics test audits these submitted transforms against the real meshes and independent Terrain rays. The native `art_direction_preview.gd` harness additionally compares actual renderer transform readback with the submitted values.

Only the separate rock kit is exported here. This builder does not change the authored cave layout, main mine GLB, terrain collision, mine props, or player equipment.
