# Gravebound player model

Dedicated player asset derived from the generated dark fantasy character concepts
at `../../concept-art/player_gravebound/concept_front.png`, `concept_back.png`,
and `concept_side.png`.

## Rebuild

Run the local Blender executable in background mode with `build_player.py`.
The builder constructs the hood, curved shoulder mantle, continuous padded
sleeves, split quilted coat, belt, pouches, fingerless gloves and separate fingers,
trousers and continuous boots as actual volumetric geometry. The anatomical head
and eyes are derived from the existing CC0/MakeHuman-based mercenary source;
that source is read without modification.

Front, rear and side projections are blended using the surface normal, then
baked to a shared 4096×4096 atlas. Rear projection mirrors horizontal image
coordinates to match the back camera. Side projection maps each garment's depth
to a safe region of the dedicated profile reference, preserving woven cloth and
leather detail across the sides. The inner neck cowl samples clasp-free folded
hood cloth and has an open neck with real cloth thickness. Sleeves end inside
their bracers to avoid intersecting surfaces.

The atlas is baked in one combined-mesh operation with 3-pixel dilation and wider
UV-island spacing. This prevents the sequential object padding contamination
that produced the light sleeve artefact in earlier revisions. The runtime asset
retains its 50 separate meshes.
The exported
runtime material is ordinary non-emissive PBR with roughness 0.9. Runtime meshes
have one UV channel (`Atlas` / `TEXCOORD_0`). The GLB contains no billboards,
transparent cutout bodies or camera-facing sprites.

`build_player.py` creates the editable `gravebound_player.blend`, the embedded
texture atlas and `../../godot-game/assets/3d/player/gravebound_player.glb`.
It also renders quiet offline front, three-quarter and back reference views
unless run with `-- --skip-previews`. The retained staging PNGs are revision 2
offline references; the final visual evidence comes from Godot screenshots.
The actual Godot screenshots and comparisons are stored separately under
`../../godot-game/artifacts/visual_qa/player_appearance/`.

## Runtime coordinates

- Godot front: **−Z**, encoded by the exported root's Y half-turn.
- Height: approximately 1.78 metres; origin at foot-centre, sole about 8 mm above zero.
- 50 actual mesh parts, 122,730 triangles, 3.79 MiB embedded GLB in revision 5.
- The full-body mesh has a static relaxed standing pose, with no baked animation,
  Skeleton3D, or locomotion animation. The inventory control rotates the model;
  the existing first-person hand/equipment animations remain a separate system.

`build_report.json` records exact bounds, names and exported size.
`finalize_export.py` is retained as a compatibility repair tool for already baked
sources; the main builder includes the same final UV and orientation rules.

## Source provenance

The front concept and matching back and side references were generated using OpenAI ImageGen for this task.
The head/eye anatomy comes from
`../blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16.blend`.
See that source folder's `SOURCES_AND_LICENSES.md` for its CC0/MakeHuman ancestry.
All new garment geometry and reconstruction code were authored for this project.
Existing character models, textures, and their original staging sources remain unchanged.
