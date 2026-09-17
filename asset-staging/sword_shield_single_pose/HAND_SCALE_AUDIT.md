# Hand scale audit and subsequent proportion correction

2026-09-07. The first section records a read-only inspection of the source builders and the GLB before subsequent proportion and wrist-tail corrections. Its “current” measurements describe that historical input, not the final applied models.

`prepare_hand.py` applies 1.08 to extracted hand coordinates; `build_assets.py` then applies 1.25 to skin vertices and digit joint positions. The current GLBs bake that scale and have unit hand node transforms. Glove geometry follows the enlarged skin.

The current middle digit has a 101.25 mm longitudinal wrist-origin-to-root distance and a 121.25 mm authored root-to-tip distance. The actual distal-weighted skin tip sample is about 124.68 mm from that root in 3D. Current wrist-to-skin-tip length is 225.48 mm. Removing only the later 1.25 scale would produce 180.38 mm; these are source-coordinate measurements, not an anthropometric certification.

No rescaling was applied in this audit. The padded-grip iteration must be assessed in actual rendered views before deciding whether another change is warranted. Any later proportion change must preserve corrected handedness, original rotations, skin weights and fitted sleeves, and update the affected contact lengths and independent actual-skin tests consistently. Equipment dimensions and forearm lengths must not be scaled with hand-local coordinates.

## Subsequent applied length-only revision

The `single_pose_padded_08` renderer and two independent visual reviews rejected the open C-shaped shield grip. The applied correction shortens phalange-local length by 20% while preserving cross-section width/thickness, MCP anchors, palm, wrist and sleeves at this stage. The thumb metacarpal stays unchanged. Original skin weights blend the change through the joints; inverse binds follow the new rest positions. It uses the corrected arm source before the experimental 80% glove extension, restoring the original glove openings so the four finger rows can be seen. This is a proportion edit, not whole-hand scaling. [Reproduction and preservation report](proportioned_hands/README.md).

The final models then receive a separate positive-Z wrist-tail correction to reduce sleeve protrusion; finger/contact geometry is preserved in that step. [Wrist-tail report](wrist_tail_fit/README.md). All 17 final suites pass, and `single_pose_motion_03` records the applied state. [Final verification](verification/final/REVIEW.md). Successful contact and regression tests do not establish exact visual identity with the generated references.
