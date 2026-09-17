# Fingerless glove extension staging

These GLBs append one skinned leather mesh to each anatomically corrected arm.
The production files are not changed by this directory's script.

The four fingers' leather reaches 80% of the actual first phalanx, measured
along each imported bone0→bone1 axis. The thumb uses bone1→bone2 at 65%:
thumb0 is the metacarpal, already inside the original glove, rather than the
exposed proximal phalanx. Middle and distal finger contact skin remains bare;
9.2–11.8 mm of proximal skin remains before the next finger joint, and the
thumb keeps 13.7 mm before its IP joint.

`extend_gloves.py` reads the source GLB node transforms and clips triangles from
the real skin surface. Retained source vertices keep their original bone
influences; new cut-edge vertices interpolate the same influences, without
reweighting or truncation. A 1.5 mm leather shell uses the existing
`FP_WornLeather` and `FP_LeatherEdge` materials and source UVs. An overlap hides
the original glove's finger openings. Both materials are shared across all five
extensions, adding only two surfaces and one skinned mesh per arm.

The original skin, glove, sixteen joint nodes, inverse bind matrices, weights,
materials, rigid cuffs, forearms and sleeves remain byte-for-byte unchanged.
Only a new child is appended to `HandRig`. The complete original binary chunk
is an unchanged prefix of the output binary, verified after re-reading the
saved GLB. `preservation_report.json` records source/output hashes, the binary
prefix hash, per-digit axes, coverage and geometry bounds.

Reproduce with Python 3, without Blender or Godot:

```sh
python3 asset-staging/sword_shield_single_pose/glove_extension/extend_gloves.py
```

The first run snapshots the corrected originals into `source_corrected_arms/`;
later runs use those snapshots for deterministic reproduction. The original
hand attribution and license records remain those of `../corrected_arms/`.

The idle/guard captures from `single_pose_power_grip_03` and
`../references/ready_pov.png` were visually inspected before authoring.
`rest_geometry_diagnostic.png` is an untextured CPU construction diagnostic
with the added leather colored blue. It is not a game screenshot or an engine
validation result. The owning task performs production copying, importing,
contact tests and actual gameplay rendering.
