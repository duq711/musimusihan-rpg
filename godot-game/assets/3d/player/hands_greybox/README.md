# Player hands greybox

Separate review assets based on the existing Gravebound first-person arms. Created in background Blender 5.2.1 on macOS after explicit user authorization on 2026-09-10.

- Left: 9,997 triangles; right: 9,996 triangles, one 16-bone hand skin, five actual fingers.
- Native wrist and bone rest transforms retained; no negative-scale mirroring.
- Meshes reduced from 68,010 / 68,006 referenced triangles. Max bind-space AABB drift: left 0.122mm, right 0.087mm.
- Three nonmetal, texture-free neutral materials: exposed skin, glove/cuff, sleeve. The glove is a material region on the continuous hand surface; its old overlapping shell is excluded from output.
- glTF exports up to eight influences per vertex after reduction. Skin sampling must not assume four weights.
- Original input models, textures and the authored static sword grip are preserved.

The `player_hands_greybox` test-room feature enables a player-local presentation mode on the real free/utility/bow/chest hands. `greybox_arm_visual.gd` retains production contact frames and fits the reduced sleeves to actual shoulder/elbow anchors. Default sword and shield adapters keep their original assets. These are proportion and motion blockouts, not replacement final textured character art.

Editable source, Blender build/roundtrip verification and renders: `../../../../../asset-staging/player_hands_greybox_20260910/mac_output/iteration_05/` from the repository root context. The staging README contains the exact source hashes, command and validation status.

Source anatomy provenance is retained from the existing sword_shield assets (Blender Human Base Meshes, CC0 1.0). Garments and reconstruction are existing project-authored geometry. Original source notes are preserved under the staging `input/` directory.
