# BodyParts3D skeleton GLB — notice and attribution

## Asset

- Recommended file: `bodyparts3d_skeleton_cc_by_4_baked.glb`
- Alternate transform-parent file: `bodyparts3d_skeleton_cc_by_4.glb`
- Source dataset: BodyParts3D release 4.0, 99% polygon mesh archive
- Source archive: <https://dbarchive.biosciencedbc.jp/data/bodyparts3d/LATEST/partof_BP3D_4.0_obj_99.zip>
- Dataset page and DOI: <https://dbarchive.biosciencedbc.jp/en/bodyparts3d/data-8.html>, <https://doi.org/10.18908/lsdba.nbdc00837-008>
- Official license page: <https://dbarchive.biosciencedbc.jp/en/bodyparts3d/lic.html>
- License: Creative Commons Attribution 4.0 International
  (<https://creativecommons.org/licenses/by/4.0/>)

## Required attribution

> BodyParts3D, © The Database Center for Life Science licensed under CC
> Attribution 4.0 International.

## Changes made for this candidate

- Selected 202 element OBJ meshes that collectively render the complete skeleton.
- Repackaged the selected Wavefront OBJ meshes as binary glTF (`.glb`).
- Converted source millimetres/Z-up vertices and normals to metres/Y-up. In the
  recommended `_baked.glb`, this conversion is baked into every mesh so all FJ
  nodes are directly usable in identity-root runtime pivot space. The alternate
  file stores the same conversion on a parent transform.
- Preserved the source `FJ…` element identifiers as mesh-node names.
- No topology, vertex position, or anatomical shape was intentionally changed.

CC BY 4.0 permits commercial use, redistribution, and adaptation. Attribution,
a license link, and an indication of modifications are required. It has no
ShareAlike condition and does not require release of game source code.

## Reproducibility and integrity

- Source ZIP SHA-256:
  `9fbc713fffeee924a5a657d9813d84d7eb957bded63adb854931dd5e3eb61c97`
- Recommended baked GLB SHA-256:
  `3ff9ee03c42defe122027cba2887a9728924ca3764b52b3d91d46bd42ab33151`
- Recommended GLB: 14,587,712 bytes; 202 meshes; 513,164 triangles; no skin;
  no animation; no material or texture.
- Conversion script: `../export_bodyparts3d_baked_glb.gd`
- Godot 4.7 imported the GLB and rendered all 202 meshes successfully.
