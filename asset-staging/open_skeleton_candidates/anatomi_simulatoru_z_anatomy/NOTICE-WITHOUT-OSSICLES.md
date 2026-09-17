# Z-Anatomy skeleton without auditory ossicles — conservative notice

## Asset

- File: `iskelet_without_ossicles.glb`
- Immediate source: `systems/iskelet.glb` from Anatomi Simülatörü
- Immediate source repository: <https://github.com/DrMuratAltun/anatomi-simulatoru>
- Direct original GLB: <https://raw.githubusercontent.com/DrMuratAltun/anatomi-simulatoru/main/systems/iskelet.glb>
- Upstream: Z-Anatomy, <https://github.com/Z-Anatomy/Models-of-human-anatomy>
- Original anatomical database: BodyParts3D, DBCLS,
  <https://dbarchive.biosciencedbc.jp/en/bodyparts3d/>
- License of this derivative GLB: CC BY-SA 4.0,
  <https://creativecommons.org/licenses/by-sa/4.0/>

## Attribution

> BodyParts3D, © The Database Center for Life Science (DBCLS). Z-Anatomy —
> The libre 3D atlas of anatomy. Web-ready GLB conversion by Dr. Murat Altun /
> Anatomi Simülatörü. This adapted GLB is licensed under CC BY-SA 4.0.

When distributed, add the game's own change notice (rigging, materials,
decimation, poses, or other edits) and retain the links and license notice.

## Conservative removal made here

Z-Anatomy's official credit file says that the University of Dundee School of
Medicine's `Anatomy of the Inner Ear` was included/adapted. That source is
CC BY-NC-SA 4.0 and expressly includes the auditory ossicles. Because Z-Anatomy
does not provide per-object provenance, this file physically removes these six
nodes and their mesh data before any potential commercial use:

- `Incus.l`, `Incus.r`
- `Malleus.l`, `Malleus.r`
- `Stapes.l`, `Stapes.r`

The removal is a conservative provenance measure, not proof that all remaining
geometry is free from third-party claims and not legal advice. The result remains
CC BY-SA 4.0; the removal does not relicense it.

## Integrity

- Original GLB SHA-256:
  `43b4b27487db537e2e1ae2c87d3408f8d22943eb03eb6415a2833c865d82e4cf`
- This GLB SHA-256:
  `c064affaf7d0f6363fad59ba88ae3b40c347aa815a6a66a1d1cec2b24b268f20`
- This GLB: 5,115,884 bytes; 271 nodes; 227 meshes; 310,287 triangles;
  no skin; no animation; no material or texture.
- Removal script: `strip_noncommercial_ossicles.py`
- Godot 4.7 imported and rendered all 271 remaining mesh instances.

