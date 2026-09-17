# Sources and Licenses

This file records the source and provenance of the game-ready mercenary
character. It applies to the editable Blender file, exported Godot GLB,
procedural texture maps, preview renders, and retained modeling references in
this staging directory.

## MPFB / MakeHuman Human Base

- Authoring add-on: MPFB 2.0.17 (MakeHuman Plugin for Blender)
- Project: https://github.com/makehumancommunity/mpfb2
- Generated human-system assets: MakeHuman Community system asset pack
- Asset license: Creative Commons Zero 1.0 (CC0 1.0)

The character's anatomically reliable head/neck, eyes, eyebrows, body scale,
neutral T-pose, and Rigify alignment start from the MPFB/MakeHuman base.  The
base was reshaped toward the supplied reference and combined with separately
reconstructed clothing geometry.  MPFB was used as an authoring tool; it is not
required at Godot runtime.

## Procedural Texture Maps

The skin, gambeson, outer-coat wool, cowl wool, leather, and hair-card maps in
`textures/` were generated locally by the project's deterministic procedural
texture workflow. They do not incorporate downloaded third-party texture maps.
The generated maps are packed or referenced by the Blender scene and embedded
in the exported GLB as appropriate.

## OpenAI ImageGen-Derived Modeling References

- `references/mercenary_tpose_front.png`
- `references/mercenary_tpose_back.png`

These T-pose images were derived with OpenAI ImageGen from the user-provided
mercenary concept references.  They were used as reconstruction inputs and as
front/back projected base-colour references so the face, clothing layout, and
silhouette remain close to the supplied design.  The processed projection maps
are retained in `textures/reference_projection_*_basecolor_4k.png` and are
packed into or referenced by the production Blender/GLB asset.

## Rigging Tool

The editable character uses a Rigify-generated full-body rig. Rigify is part of
Blender's add-on ecosystem and was used as an authoring tool; no separate
third-party rig or animation asset was imported.

## Image-to-3D Reconstruction

- Reconstructor: TripoSR
- Official project: https://github.com/VAST-AI-Research/TripoSR
- Code/model license stated by the project: MIT
- Input: the generated, equipment-free front T-pose reference
- Output retained at: `triposr/mercenary_tpose_triposr_raw.glb`

The user explicitly allowed uploading the references to an external
image-to-3D service.  An official public TripoSR demo was used to reconstruct a
coarse clothing-and-silhouette donor mesh.  The donor was then rescaled,
reoriented, retopology-budgeted, rematerialed, and bound to a fresh Rigify rig
locally in Blender.  The external output was not accepted as game-ready without
those local production and validation steps.

## Deliberately Excluded Equipment

The final character excludes weapons and utility equipment that were not part
of the requested modeling priority, including:

- crossbow, bolts/arrows, and quiver;
- sword, dagger, knife, scabbard, and sheath;
- belt pouches and satchels.

The retained belts, straps, buckles, gloves, and boots are clothing components,
not separate weapon or inventory props.
