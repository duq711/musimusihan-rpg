# Procedural dark-fantasy GLB staging kit

This is an isolated asset lab. It does not reference or modify the game project.

## Toolchain

- Godot 4.7's built-in `SurfaceTool`, primitive meshes, PBR materials, and `GLTFDocument`
- No Blender, paid package, external model, or downloaded texture is required
- All geometry is deterministic and generated from `generate_assets.gd`

Run on this machine:

```sh
"/Users/duq711gmail.com/Downloads/Godot.app/Contents/MacOS/Godot" \
  --headless --path . --script generate_assets.gd
```

The generator writes individual `.glb` files to `out/`:

- `sanctuary_warden_3d.glb` — 2.12 m black-iron undead knight, articulated pivots, longsword
- `ossuary_keeper_3d.glb` — 1.92 m hunched skeletal keeper, articulated pivots, cleaver
- `rusted_longsword.glb` — +Y blade, pivot at hilt, grip/tip anchors
- `weathered_round_shield.glb` — +Z front, rear hand anchor
- `iron_cage_torch.glb` — +Y shaft, grip/flame anchors; light is added in game code
- `reliquary_chest.glb` — barrel-vault lid, lock rune, interaction/lid markers
- `blood_rune_trap.glb` — 1.8 m floor plate, emissive runes, damage marker
- `sanctum_portal_arch.glb` — 3 m arch, translucent portal, interaction/target markers
- `dungeon_floor_4m.glb` — 4 m modular floor
- `dungeon_wall_4m.glb` — 4 m x 3 m modular wall
- `dungeon_archway_4m.glb` — matching wall module with 1.7 m opening
- `dungeon_pillar_3m.glb` — 3.1 m freestanding pillar
- `dungeon_stairs_4m.glb` — ten-step 4 m stair module

After a Godot import pass, scene structure can be checked with:

```sh
"/Users/duq711gmail.com/Downloads/Godot.app/Contents/MacOS/Godot" \
  --headless --path . --script validate_assets.gd
```

The enemy-specific contract validator additionally checks scale, foot origin,
collision absence, mesh-selection prefixes, glowing eyes, weapon ownership, and
every runtime pivot:

```sh
"/Users/duq711gmail.com/Downloads/Godot.app/Contents/MacOS/Godot" \
  --headless --path . --script validate_enemy_assets.gd
```

Both enemies face Godot forward (`-Z`), stand on `y=0`, and use this shared hierarchy:

```text
Root
└── VisualRoot
    ├── TorsoPivot
    │   ├── HeadPivot
    │   ├── ArmLPivot
    │   └── ArmRPivot
    │       └── WeaponPivot
    ├── LegLPivot
    └── LegRPivot
```

All enemy `MeshInstance3D` names begin with `Armor`, `Cloth`, `Bone`, `Weapon`,
or `Eye`, allowing the game to select parts for hit flashes and material changes.
No `AnimationPlayer` or collision object is exported; runtime code rotates the
pivots and keeps the game's existing `CharacterBody3D` collision.

For optional GPU-rendered thumbnails, run `render_previews.gd` without
`--headless`; it writes `previews/contact_sheet.png` and one PNG per asset.
Run `render_enemy_previews.gd` the same way for a front, three-quarter, side,
and back turntable sheet at `previews/enemies/enemy_contact_sheet.png`.

Godot import suffixes such as `-colonly` are used on simple collision proxy meshes.
The current game may instead retain its authored collision bodies and use these GLBs
only as visual children, which is often the safer first integration pass.

## Visual limits

This kit supplies coherent silhouettes, scale, material response, anchors, and readable
detail. Because it deliberately uses no texture files, it is a polished low-poly base,
not a photogrammetric result. A later texture pass can add stone normals, grunge masks,
wood grain, and baked ambient occlusion without changing any gameplay code or pivots.
