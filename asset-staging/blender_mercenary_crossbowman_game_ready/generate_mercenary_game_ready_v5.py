"""Build v5 by repairing the v3 upper-torso cut without regressing limb cleanup.

The v3 donor-cowl cleanup used a broad spatial ellipse and then deleted every
central face classified as cowl.  That removed valid chest, clavicle and
shoulder faces together with the old collar shell.  V5 keeps the donor below
the neck line and removes only (1) the original high collar region and
(2) donor faces that actually intersect the clean replacement cowl.
"""

from __future__ import annotations

import os
from pathlib import Path


WORKSPACE = Path(os.getcwd())
STAGING_DIR = WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
V3_SCRIPT = STAGING_DIR / "generate_mercenary_game_ready_v3.py"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"v5 patch {label!r} expected one match, found {count}")
    return source.replace(old, new, 1)


# Reuse the validated v3 pipeline, but write independent v5 artifacts.
source = V3_SCRIPT.read_text(encoding="utf-8")
source = source.replace("v3", "v5").replace("V3", "V5")

old_broad_cowl_cut = '''# Remove only the noisy central donor cowl/inner shell.  This tighter ellipse
# preserves the shoulder caps while clearing the volume occupied by the clean
# layered cowl appended below.
donor_cowl_triangles_removed = filter_faces_in_place(
    donor,
    lambda center, poly: not (
        1.390 < center.z < 1.610
        and (
            (center.x / 0.292) ** 2
            + ((center.y - 0.008) / 0.225) ** 2
        )
        < 1.0
    ),
)'''
new_high_collar_cut = '''# Preserve every chest, clavicle and shoulder face here.  The replacement cowl
# is resolved later from material identity plus exact BVH contact, so no broad
# coordinate mask is allowed to cut the donor upper torso.
donor_cowl_triangles_removed = 0'''
source = replace_once(
    source,
    old_broad_cowl_cut,
    new_high_collar_cut,
    "preserve chest and shoulder donor faces",
)

old_shard_cut = '''donor_shard_bm = bmesh.new()
donor_shard_bm.from_mesh(donor.data)
donor_shard_faces = [
    face
    for face in donor_shard_bm.faces
    if (
        1.455 < face.calc_center_median().z < 1.635
        and abs(face.calc_center_median().x) < 0.380
        and face.material_index == 5
    )
]
donor_cowl_shard_triangles_removed = sum(
    max(1, len(face.verts) - 2) for face in donor_shard_faces
)
if donor_shard_faces:
    bmesh.ops.delete(donor_shard_bm, geom=donor_shard_faces, context="FACES")'''
new_exact_cowl_cut = '''donor_shard_bm = bmesh.new()
donor_shard_bm.from_mesh(donor.data)

# Remove residual donor collar faces only above the clavicle.  V3 began this
# blanket removal at z=1.455, which cut the upper chest and shoulder bridge.
donor_shard_faces = [
    face
    for face in donor_shard_bm.faces
    if (
        1.430 < face.calc_center_median().z < 1.600
        and abs(face.calc_center_median().x) < 0.255
        and face.material_index == 5
    )
]
donor_cowl_shard_triangles_removed = sum(
    max(1, len(face.verts) - 2) for face in donor_shard_faces
)
if donor_shard_faces:
    bmesh.ops.delete(donor_shard_bm, geom=donor_shard_faces, context="FACES")

# Resolve the lower cowl contact by geometry, not by a broad coordinate mask.
# Every donor triangle that actually intersects the clean cowl is removed;
# non-intersecting chest and shoulder faces remain untouched.
donor_shard_bm.faces.ensure_lookup_table()
donor_shard_bm.faces.index_update()
cowl_collision_bm = bmesh.new()
cowl_collision_bm.from_mesh(clean_cowl.data)
cowl_collision_bm.faces.ensure_lookup_table()
cowl_collision_bm.faces.index_update()
donor_collision_bvh = BVHTree.FromBMesh(donor_shard_bm, epsilon=1.0e-7)
cowl_collision_bvh = BVHTree.FromBMesh(cowl_collision_bm, epsilon=1.0e-7)
donor_cowl_collision_pairs_before_cleanup = donor_collision_bvh.overlap(
    cowl_collision_bvh
)
donor_cowl_collision_face_indices = {
    donor_face_index
    for donor_face_index, _cowl_face_index in donor_cowl_collision_pairs_before_cleanup
}
donor_cowl_collision_faces = [
    donor_shard_bm.faces[index]
    for index in sorted(donor_cowl_collision_face_indices)
    if index < len(donor_shard_bm.faces)
]
donor_cowl_collision_triangles_removed = sum(
    max(1, len(face.verts) - 2) for face in donor_cowl_collision_faces
)
if donor_cowl_collision_faces:
    bmesh.ops.delete(
        donor_shard_bm,
        geom=donor_cowl_collision_faces,
        context="FACES",
    )
cowl_collision_bm.free()'''
source = replace_once(
    source,
    old_shard_cut,
    new_exact_cowl_cut,
    "exact clean-cowl collision cleanup",
)

source = replace_once(
    source,
    '''donor_face_triangles_removed += (
    donor_cowl_shard_triangles_removed
    + donor_postcut_fragment_triangles_removed
)''',
    '''donor_face_triangles_removed += (
    donor_cowl_shard_triangles_removed
    + donor_cowl_collision_triangles_removed
    + donor_postcut_fragment_triangles_removed
)''',
    "include exact collision removal in triangle accounting",
)

source = replace_once(
    source,
    '''    "donor_cowl_shard_triangles_removed": donor_cowl_shard_triangles_removed,
    "donor_postcut_fragment_triangles_removed": donor_postcut_fragment_triangles_removed,''',
    '''    "donor_cowl_shard_triangles_removed": donor_cowl_shard_triangles_removed,
    "donor_cowl_collision_pairs_before_cleanup": len(
        donor_cowl_collision_pairs_before_cleanup
    ),
    "donor_cowl_collision_triangles_removed": donor_cowl_collision_triangles_removed,
    "donor_postcut_fragment_triangles_removed": donor_postcut_fragment_triangles_removed,''',
    "record exact cowl collision cleanup",
)

# V3's limb material pass began at |x| > 0.21, which includes the clavicle,
# upper chest and most shoulder-cap faces.  Restrict it to the actual arm span
# and keep the same boundary in the no-projection assertion.
limb_rule = "if z > 1.18 and ax > 0.21:"
if source.count(limb_rule) != 2:
    raise RuntimeError(
        "v5 expected two v3 limb material rules, found %d"
        % source.count(limb_rule)
    )
source = source.replace(limb_rule, "if z > 1.18 and ax > 0.42:")
source = replace_once(
    source,
    "(poly.center.z > 1.18 and abs(poly.center.x) > 0.21)",
    "(poly.center.z > 1.18 and abs(poly.center.x) > 0.42)",
    "limit limb projection QA to actual arms",
)

# The clean cowl is its own object and always receives material 5.  Surviving
# donor faces at the upper torso are the dark outer vest, not another cowl.
old_upper_vest_rule = '''    if z > 1.40:
        return 5  # cowl
    return 4  # torso outer wool'''
new_upper_vest_rule = '''    if z > 1.40:
        return 4  # preserved upper vest and shoulder bridge
    return 4  # torso outer wool'''
if source.count(old_upper_vest_rule) != 2:
    raise RuntimeError(
        "v5 expected old/new v3 upper-vest literals, found %d"
        % source.count(old_upper_vest_rule)
    )
# The first occurrence is v3's exact-match template for the original v2 source;
# only the second occurrence is the replacement material function.
upper_vest_index = source.rfind(old_upper_vest_rule)
source = (
    source[:upper_vest_index]
    + new_upper_vest_rule
    + source[upper_vest_index + len(old_upper_vest_rule) :]
)

# Turn the lowest scarf tube into a broad, flatter shoulder mantle.  It covers
# the exact BVH contact boundary and the frayed donor edge while the two upper
# layers remain compact around the neck.
source = replace_once(
    source,
    '''cowl_drape_settings = [
    (0.90, 0.90, 0.55, 0.080, 0.0),
    (0.95, 0.92, 0.55, 0.065, 1.3),
    (1.02, 0.94, 0.55, 0.055, 2.4),
]''',
    '''cowl_drape_settings = [
    (1.43, 1.00, 0.34, 0.060, 0.0),
    (0.95, 0.92, 0.52, 0.064, 1.3),
    (1.02, 0.94, 0.52, 0.054, 2.4),
]''',
    "broaden and flatten the lower shoulder mantle",
)

compiled = compile(source, str(V3_SCRIPT) + " [v5 shoulder-mantle finish]", "exec")
exec(compiled, globals(), globals())
