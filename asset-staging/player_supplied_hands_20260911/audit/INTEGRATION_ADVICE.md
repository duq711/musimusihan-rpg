# Supplied hand: independent topology and integration advice

The directly parsed source is `Downloads/hand1.OBJ` (SHA-256 recorded in `obj_topology.json`). The existing integration rig has sixteen bones: `wrist` and three named segments for each of the five digits. Its rest frames are recorded in the earlier read-only `player_fingers_detail_20260911/audit/source_structure.json`; subsequent glove verification established that those rest transforms remained unchanged.

## Measured source facts

- 596,759 vertices and 603,318 polygons, or 1,193,494 triangles after triangulation.
- One named ZBrush group, `Group17267`. This provides no anatomical separation.
- No UV coordinates, exported normals, vertex colors, material library, bone weights, or animation data.
- Six disconnected, closed manifold components. Every component has Euler characteristic 2 and zero boundary/nonmanifold edges.
- Component 0 is the hand/wrist body: 450,989 vertices and 901,974 triangles.
- Components 1–5 are five thin plate islands, each 29,154 vertices and 58,304 triangles. Their anatomical names must be confirmed from the companion visual audit before assigning rigid nail weights.
- There is no open wrist boundary to join directly. A wrist cut or an intentionally hidden cuff overlap is required if it connects to the existing forearm.
- The sole trailing NUL byte is export padding. Preserve the original file; a parser may ignore this final byte in memory.

`obj_component_labels.npy` assigns every original OBJ vertex to its connected component, preserving original vertex order.

## Recommended production approach

Use the supplied hand itself as the geometry source. Separate the six components, keep a frozen high resolution copy, align the body using a uniform scale and a rigid transform, and simplify copies of the body and each nail independently. This retains the supplied silhouette and sculpted proportions. Shrinkwrapping the previous hand toward this source would preserve the previous topology's anatomical assumptions and is not a reliable replacement.

A practical first preview target is approximately 40,000–60,000 body triangles plus 500–1,000 triangles per nail, per hand. These are starting budgets, not measured acceptance thresholds. Keep more geometry near the joints and side silhouettes, and bake the high resolution sculpt into newly generated tangent-space normal maps. The source provides no texture pixels or UV layout to preserve.

The existing sixteen-bone naming/interface can be retained, but its old anatomical rest positions should not dictate the shape of the new hand. Place joint pivots and local bending axes within the actual supplied digits. Transfer weights only after those source/destination anatomical regions are registered, and constrain transfer to matching fingers so nearby fingers do not exchange influences. Keep each entire nail island rigidly weighted to its corresponding distal `digit2` bone. Do not reuse old corrective vectors by vertex index: this source has different topology. Any retained `Joint_*` interface needs actual deformation transfer or freshly authored correctives on the new geometry.

For a natural visible wrist connection, preserve the source hand and blend the short attachment area to the forearm. A sleeve/cuff can conceal the capped wrist overlap; if a continuous bare wrist is required, cut the source cap and bridge or retopologize only that local attachment area. Avoid reshaping the palm and fingers merely to make an old wrist connector fit.

## Bounded acceptance checks for the candidate

Record the exact source-to-native transform, source component-to-digit mapping, decimation settings, and newly generated UVs. Compare the simplified neutral surface and silhouette against the aligned supplied high resolution source, excluding only an explicitly described wrist attachment area. Review each digit's actual skin/nail gap and orientation, not a generic global normal assumption. Verify weights, transformed normals, mirrored winding, bone names, joint resets, and the actual exported texture bindings. Finally check the new model in the existing bow, chest, and hand-joint game poses. Numerical source fidelity and visible pose quality are separate checks.

This is advice for the new replacement task. It does not carry forward the cancelled photoref or mercenary-glove preservation contracts as restrictions on replacing the user's hand geometry.
