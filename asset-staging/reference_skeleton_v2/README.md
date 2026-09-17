# Reference Skeleton V2

Deterministic Godot 4.7 generator for a fully three-dimensional, unarmoured
adult skeleton enemy. The source image is used only as anatomical and material
reference; no pixels or watermark from it are included.

## Build and QA

```sh
GODOT="/Users/duq711gmail.com/Downloads/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --script generate_reference_skeleton.gd
"$GODOT" --headless --path . --import --quit
"$GODOT" --headless --path . --script validate_reference_skeleton.gd
"$GODOT" --headless --path . --script render_reference_previews.gd
```

Outputs:

- `out/reference_skeleton_3d.glb`
- `textures/weathered_bone_albedo.png`
- `previews/reference_skeleton_v2_{front,three_quarter,side,back}.png`
- `previews/reference_skeleton_v2_contact_sheet.png`

## Validated contract

- GLB 2.0, 2.4 MB, 280 independent three-dimensional bone meshes
- 1.943 m imported height, feet at y=0.015 m, -Z forward
- 12 left and 12 right ribs; sternum, 20 vertebral bodies, clavicles and scapulae
- open pelvic foramina and independent sacrum, ilia, pubic rami and ischia
- each hand: 8 carpals, 5 metacarpals and 14 phalanges
- each foot: talus/calcaneus/navicular/cuneiforms, 5 metatarsals and 14 phalanges
- no collision, armour, cloth, hood, weapon, luminous eye or emissive material
- right-hand compatibility hierarchy: `WristRPivot/WeaponPivot/HandRPivot`

The generator also renders a source-inspired raised-arm pose to prove that the
shoulder, elbow, wrist, hip and knee pivots can articulate independently.
