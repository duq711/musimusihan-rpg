# Sword and shield hand audit

The original hand pair was assigned to the wrong equipment sides. This is a
geometry identity defect, not an axial wrist-roll issue.

## Evidence

- `asset-staging/sword_shield_first_person/canonical_hand_back.png` shows the
  fingernails and dorsal face, with fingers upward and the thumb on the right:
  it is a **left** hand. The paired palm image confirms the surface identity.
- `prepare_hand.py` places that dorsal camera at canonical +Z. The glTF export
  maps canonical fingers +Y to Godot -Z, and dorsal +Z to Godot +Y.
- For fingers -Z and dorsum +Y, the anatomical right thumb is on -X; the left
  thumb is on +X. This relation is invariant under any proper wrist rotation.
- `build_assets.py` incorrectly described the canonical mesh as a right hand
  and assigned `reflection=1` to `right_arm.glb`.
- Before correction, the right-labelled `thumb0` has X=+37.5 mm and the
  left-labelled `thumb0` has X=-37.5 mm. They have the opposite identities.
- The old test `thumb0.x * hand_side > 0` repeated the exporter’s wrong sign. It
  did not independently establish anatomical chirality.

The resulting sword grip presented the finger row on the outside edge. Rolling
that wrong hand changed its silhouette but could not turn it into a right hand.

## Staged correction

`correct_handedness.py` transplants only each opposite **HandRig** subtree,
including continuous skin, glove, sixteen joints, and inverse bind matrices.
Every donor hand attribute payload is copied byte-for-byte. The recipient’s
Forearm, UpperArm, WristCuff, materials, transforms, and original binary remain
unchanged. Both outputs retain one skin record and the original scene node count.
No runtime negative scale is introduced. `handedness_report.json` records the
donor signatures and new anatomical thumb positions.

This builder reads its preserved source pair and writes staging GLBs only. It
does not invoke Blender or Godot and never modifies production assets.

The matching runtime conventions are:

| Equipment role | Geometry thumb/index side | Shaft/strap upward axis |
|---|---:|---|
| Right sword hand | local -X | hand X = -blade Y |
| Left shield hand | local +X | hand X = +RearGrip axis |

The elbowward Z direction remains anatomical. Y is reconstructed as Z cross X.
Keeping the old shaft-axis sign after exchanging the hand meshes would reverse
the index-to-little ordering along the grip.

## Thumb contact defect

The former sword thumb target was 31.7569 mm from the nominal shaft axis. Its
test checked only the index-side X range and a minimum thumb/index separation,
so a visibly floating thumb passed. It also did not verify the thumb pad normal.

The corrected nominal sword target lies at radius 19.7 mm, and the shield thumb
targets the opposite ribbon face with 2 mm clearance. The thumb CMC has a bounded
0.75-radian metacarpal opposition rotation, mirrored by actual anatomical side.
Existing hinge-flexion and lateral-adduction limits remain unchanged. This
allows the soft thumb pad, rather than its lateral edge, to meet the object.
The sword thumb pad meets the shaft at 175 degrees around its nominal cross
section. This allows its actual palmar surface to face the object without
extending the CMC or IP limits. Independent weighted-skin calculations gave
nominal target errors below 0.1 mm and inward-normal alignment of 0.715–0.717
over closed grip tensions 0.75–1.0. The innermost sampled skin radius was at
least 17.317 mm, outside the nominal 17.2 mm shaft.

The production sword is an **oval** from `sword_geometry.py`, not the old nominal
circle. `set_sword_grip_surface(weapon_from_hand)` therefore projects all sword
finger targets onto the authored ellipse plus its 0.66 mm average wrap layer,
with 1.2–2.0 mm normal clearance and an additional 0.4 mm for the curved thumb
pad's actual skin thickness. The folded wrap varies by about 0.14 mm around
that layer. Wrist transform and tension are quantized for a bounded pose cache;
unchanged inputs do not rerun contact solving. Full mesh contact checks belong
to the actual player fixture; nominal-circle checks are labelled as such.

## Imported bone-pose rotation defect

A second independent defect discarded each finger's imported local rotation.
`set_bone_pose_rotation()` sets a parent-relative local rotation; it does not
apply a delta after the rest rotation. The official documentation describes
the parent-relative coordinate space, and `reset_bone_pose()` explicitly copies
the rest-basis quaternion into the pose. See the
[Skeleton3D API](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html#class-skeleton3d-method-set-bone-pose-rotation)
and [Godot's implementation](https://github.com/godotengine/godot/blob/master/scene/3d/skeleton_3d.cpp).

The prior identity reset removed the source thumb CMC abduction and finger
orientations. A position-only solver could still reach a point while placing
the side of the thumb against the object, which explains why pad-distance
checks passed while the independent rendered-surface normal check failed.

The runtime now stores the actual imported rotation of every joint. Opening
restores that quaternion; articulation uses `imported_rotation * joint_delta`.
Caching stores those complete local poses. The wrist, original bind data and
joint-angle limits remain unchanged. The test assertion that an open finger's
local quaternion had to be identity was also based on the wrong convention.

Using the real debug fixture matrices and imported GripLeather/GripBinding
triangles, independent CPU skin calculations predict the following corrected
values, pending the root agent's engine test:

| Pose | Pad normal toward contacted face | Mean surface gap | Deepest skin sample |
|---|---:|---:|---:|
| Idle | 0.634 | 1.885 mm | -0.342 mm |
| Guard | 0.587 | 1.876 mm | -0.380 mm |

The actual engine validation retains its previous thresholds. No test tolerance
was widened to obtain these values.

## Validation boundary

This change corrects handedness and contact construction. It does not establish
photographic resemblance or approve the prior wrist-roll animation. Root owns
production GLB installation, engine import, integrated tests, and single-pose
renderer comparison against the new references. Those checks are required
before accepting the visual result.
