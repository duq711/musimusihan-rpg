# Blender hideout ruin kit

Seven original decorative mesh assets made with Blender 5.2.1 LTS in background
mode. `hideout_ruins_kit.blend` is the editable collection-organized library.
`build_ruin_kit.py` reconstructs all geometry with a fixed random seed and exports
only the selected mesh to the Godot project. It does not open or replace the
user's active Blender file. No external assets, downloads, or plug-ins are needed.

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python asset-staging/hideout_ruins_blender/build_ruin_kit.py
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python asset-staging/hideout_ruins_blender/render_ruin_kit.py
```

Exports are in `godot-game/assets/3d/hideout_ruins/`. They contain mesh geometry,
UV coordinates, portable vertex colors, and neutral rough material slots, with
no cameras, lights, animation, collision, or runtime scripts. Godot controls
placement, weathering shaders, collision, water particles, and room lighting.

| File stem | Origin | Purpose |
| --- | --- | --- |
| broken_masonry_edge | Floor center | Uneven remaining wall with missing blocks and chipped corners |
| collapsed_arch | Floor center | Fallen arch voussoirs, broken feet, and scattered rubble |
| rubble_pile | Floor center | Dense mound of varied fractured stone chips |
| snapped_timber | Floor center | Longitudinal rotten splinters with a ragged broken end |
| hanging_roots | **Top anchor** | Forked ceiling roots; geometry hangs into negative Godot Y |
| moss_clump | Floor center | Irregular raised moss lobes with short leaf tufts |
| ceiling_spall | **Top anchor** | Flaking limestone and calcite dripstone, hanging into negative Y |

Coordinates are glTF/Godot **Y up, meters**. `build_report.json` records exact
Godot-space bounds, triangle counts, material slots, and export SHA-256 hashes.
Minor below-floor overlap on rubble/stone feet is intentional to avoid floating
contact. Floorcenter origins remain exactly `(0, 0, 0)`. Root/spall anchors are
also `(0, 0, 0)` and are intended to be placed against ceilings.

Materials: `ruin_stone`, `ruin_timber`, `ruin_moss`, `ruin_root`, `ruin_mortar`.
Vertex tint uses the `RuinTint` attribute and exports as glTF `COLOR_0`. To keep
this baked variation when replacing materials, enable vertex-color albedo on
the replacement material. Models are static accents and have no collision;
use pre-existing room collision and keep rubble out of necessary passages.

`qa/` holds individually rendered asset checks, not room concepts or gameplay
screenshots. Actual room screenshot matching is performed by the Godot hideout
preview workflow after placement.
