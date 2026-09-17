"""Generate a clean mercenary v3 without mutating the validated v2 script.

The complete v2 authoring pipeline is reused from source, but a small set of
auditable transformations is applied *in memory* before execution.  This keeps
all raw imports, 4K texture work, Rigify generation, weighting, rendering and
real-skinned GLB export identical while fixing the v2 defects:

* the replacement MPFB object retained an upper-torso patch while the donor
  removed only its front face, creating overlapping head/neck/cowl shells;
* upper sleeve side faces were classified as dark cowl before the arm rule;
* flat iris/pupil cylinders read as artificial discs in close portraits.

Every v3 artifact has a separate name/path, so no v2 or production file is
overwritten while the candidate is being reviewed.
"""

from __future__ import annotations

import os
from pathlib import Path


WORKSPACE = Path(os.getcwd())
STAGING_DIR = (
    WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
)
V2_SCRIPT = STAGING_DIR / "generate_mercenary_game_ready_v2.py"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"v3 patch {label!r} expected one match, found {count}")
    return source.replace(old, new, 1)


source = V2_SCRIPT.read_text(encoding="utf-8")

# Separate candidate artifacts.  The v2 script and the unversioned production
# GLB remain untouched throughout v3 generation and QA.
source = replace_once(
    source,
    'BLEND_PATH = os.path.join(STAGING_DIR, "mercenary_crossbowman_game_ready_v2.blend")',
    'BLEND_PATH = os.path.join(STAGING_DIR, "mercenary_crossbowman_game_ready_v3.blend")',
    "blend output",
)
source = replace_once(
    source,
    '    "godot-game/assets/3d/dark_fantasy/mercenary_crossbowman_game_ready_3d.glb",',
    '    "godot-game/assets/3d/dark_fantasy/mercenary_crossbowman_game_ready_v3.glb",',
    "GLB output",
)
source = replace_once(
    source,
    'SUMMARY_PATH = os.path.join(STAGING_DIR, "build_summary_v2.json")',
    'SUMMARY_PATH = os.path.join(STAGING_DIR, "build_summary_v3.json")',
    "summary output",
)

# The MPFB replacement is now the actual cranium/head only.  v2's z>1.355
# subset accidentally retained a rectangular torso/cowl patch down to z=1.3515.
source = replace_once(
    source,
    '    lambda center, poly: center.z > 1.355 and abs(center.x) < 0.145,',
    '    lambda center, poly: center.z > 1.49 and abs(center.x) < 0.154,',
    "MPFB head-only subset",
)

# Face-center subsetting can leave a sawtooth row of vertices below the desired
# neckline.  Bisect it on an exact horizontal plane so the retained MPFB head
# ends at one clean, cowl-hidden seam.
head_anchor = '''head = subset_mesh_object(
    full_body,
    "Mercenary_Male_HeadNeck_LOD0",
    asset_collection,
    lambda center, poly: center.z > 1.49 and abs(center.x) < 0.154,
)
bpy.data.objects.remove(full_body, do_unlink=True)'''
head_injection = '''head = subset_mesh_object(
    full_body,
    "Mercenary_Male_HeadNeck_LOD0",
    asset_collection,
    lambda center, poly: center.z > 1.49 and abs(center.x) < 0.154,
)
import bmesh

head_bm = bmesh.new()
head_bm.from_mesh(head.data)
bmesh.ops.bisect_plane(
    head_bm,
    geom=list(head_bm.verts) + list(head_bm.edges) + list(head_bm.faces),
    dist=1.0e-6,
    plane_co=Vector((0.0, 0.0, 1.49)),
    plane_no=Vector((0.0, 0.0, 1.0)),
    clear_inner=True,
    clear_outer=False,
)
loose_head_vertices = [vertex for vertex in head_bm.verts if not vertex.link_faces]
if loose_head_vertices:
    bmesh.ops.delete(head_bm, geom=loose_head_vertices, context="VERTS")
bmesh.ops.triangulate(head_bm, faces=list(head_bm.faces))
head_bm.to_mesh(head.data)
head_bm.free()
head.data.update()
if min(vertex.co.z for vertex in head.data.vertices) < 1.489:
    raise RuntimeError("V3 MPFB head plane cut failed")
bpy.data.objects.remove(full_body, do_unlink=True)'''
source = replace_once(source, head_anchor, head_injection, "exact MPFB neckline")

# Replace—not augment—the old front-face-only deletion.  The unified AABB owns
# the same spatial volume as the replacement head and therefore removes the old
# donor face, rear cranium and side cranium without cutting the surrounding
# donor cowl.  A small positive margin absorbs the later face-depth alignment.
old_donor_cut = '''# Remove the donor's front-center facial shell so the MPFB face cannot z-fight or
# be occluded. Keep the upper/side hair mass and the surrounding cowl silhouette.
donor_face_triangles_removed = filter_faces_in_place(
    donor,
    lambda center, poly: not (
        1.46 < center.z < 1.73
        and abs(center.x) < 0.17
        and center.y < 0.0
    ),
)'''
new_donor_cut = '''# Remove the donor's complete central head volume exactly once.  A smooth
# capsule boolean avoids the jagged open AABB boundary produced by face-center
# deletion while preserving the surrounding shoulder/cowl shell.
donor_triangles_before_head_cut = triangle_count(donor)
cutter_rings = [
    (1.445, 0.020, 0.025),
    (1.462, 0.170, 0.190),
    (1.500, 0.170, 0.190),
    (1.550, 0.160, 0.185),
    (1.650, 0.140, 0.170),
    (1.740, 0.105, 0.135),
    (1.800, 0.055, 0.070),
    (1.820, 0.012, 0.016),
]
cutter_segments = 64
cutter_vertices = []
cutter_faces = []
for z, radius_x, radius_y in cutter_rings:
    for segment in range(cutter_segments):
        angle = math.tau * segment / cutter_segments
        cutter_vertices.append(
            (
                radius_x * math.cos(angle),
                0.030 + radius_y * math.sin(angle),
                z,
            )
        )
for ring_index in range(len(cutter_rings) - 1):
    for segment in range(cutter_segments):
        nxt = (segment + 1) % cutter_segments
        lower = ring_index * cutter_segments
        upper = (ring_index + 1) * cutter_segments
        cutter_faces.append(
            (lower + segment, lower + nxt, upper + nxt, upper + segment)
        )
cutter_faces.append(tuple(reversed(range(cutter_segments))))
top_start = (len(cutter_rings) - 1) * cutter_segments
cutter_faces.append(tuple(top_start + index for index in range(cutter_segments)))
cutter_mesh = bpy.data.meshes.new("_V3_DonorHeadCut_Capsule_Mesh")
cutter_mesh.from_pydata(cutter_vertices, [], cutter_faces)
cutter_mesh.update()
cutter = bpy.data.objects.new("_V3_DonorHeadCut_Capsule", cutter_mesh)
asset_collection.objects.link(cutter)
head_boolean = donor.modifiers.new("V3_SmoothHeadVolumeCut", "BOOLEAN")
head_boolean.operation = "DIFFERENCE"
head_boolean.solver = "EXACT"
head_boolean.object = cutter
apply_modifier(donor, head_boolean)
bpy.data.objects.remove(cutter, do_unlink=True)
donor_boolean_difference_triangles = max(
    0, donor_triangles_before_head_cut - triangle_count(donor)
)


def _v3_inside_cutter_envelope(center):
    z = center.z
    if z < cutter_rings[0][0] - 1.0e-5 or z > cutter_rings[-1][0] + 1.0e-5:
        return False
    lower = cutter_rings[0]
    upper = cutter_rings[-1]
    for index in range(len(cutter_rings) - 1):
        candidate_lower = cutter_rings[index]
        candidate_upper = cutter_rings[index + 1]
        if candidate_lower[0] <= z <= candidate_upper[0]:
            lower, upper = candidate_lower, candidate_upper
            break
    blend = (z - lower[0]) / max(1.0e-8, upper[0] - lower[0])
    radius_x = lower[1] * (1.0 - blend) + upper[1] * blend
    radius_y = lower[2] * (1.0 - blend) + upper[2] * blend
    normalized = (
        (center.x / max(1.0e-8, radius_x)) ** 2
        + ((center.y - 0.030) / max(1.0e-8, radius_y)) ** 2
    )
    return normalized <= 1.035 ** 2


# Boolean difference creates a closed interior wall.  Remove only faces on that
# cutter envelope, leaving a clean open neckline instead of a textured chest cap.
donor_boolean_wall_triangles_removed = filter_faces_in_place(
    donor,
    lambda center, poly: not _v3_inside_cutter_envelope(center),
)
donor_face_triangles_removed = (
    donor_boolean_difference_triangles + donor_boolean_wall_triangles_removed
)

# Remove only the noisy central donor cowl/inner shell.  This tighter ellipse
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
)
donor_face_triangles_removed += donor_cowl_triangles_removed

# Reuse the clean, closed layered cowl authored in the preserved v1 source.
v1_blend = os.path.join(STAGING_DIR, "mercenary_crossbowman_game_ready_3d.blend")
with bpy.data.libraries.load(v1_blend, link=False) as (cowl_from, cowl_to):
    cowl_to.objects = [
        name
        for name in ["Cloth_Cowl_LayeredHeavyWool"]
        if name in cowl_from.objects
    ]
if not cowl_to.objects or cowl_to.objects[0] is None:
    raise RuntimeError("Clean v1 layered cowl missing")
clean_cowl = cowl_to.objects[0]
asset_collection.objects.link(clean_cowl)
clean_cowl.name = "Mercenary_Cowl_LayeredClean_LOD0"
clean_cowl.data.name = "Mercenary_Cowl_LayeredClean_LOD0_Mesh"
clean_cowl.parent = None
clean_cowl.matrix_world.identity()
for modifier in list(clean_cowl.modifiers):
    clean_cowl.modifiers.remove(modifier)
# The v1 cowl contains three clean, closed components.  Compress and stagger
# them into a draped scarf rather than leaving three oversized horizontal
# tubes.  Small deterministic angular folds break the perfect-ring silhouette.
cowl_neighbors = [set() for _ in clean_cowl.data.vertices]
for edge in clean_cowl.data.edges:
    a, b = edge.vertices
    cowl_neighbors[a].add(b)
    cowl_neighbors[b].add(a)
cowl_remaining = set(range(len(clean_cowl.data.vertices)))
cowl_components = []
while cowl_remaining:
    seed = cowl_remaining.pop()
    component = {seed}
    stack = [seed]
    while stack:
        current = stack.pop()
        for neighbor in cowl_neighbors[current]:
            if neighbor in cowl_remaining:
                cowl_remaining.remove(neighbor)
                component.add(neighbor)
                stack.append(neighbor)
    cowl_components.append(component)
if len(cowl_components) != 3:
    raise RuntimeError(
        "Expected three closed v1 cowl layers, found %d" % len(cowl_components)
    )
cowl_components.sort(
    key=lambda component: min(
        clean_cowl.data.vertices[index].co.z for index in component
    )
)
cowl_drape_settings = [
    (0.90, 0.90, 0.55, 0.080, 0.0),
    (0.95, 0.92, 0.55, 0.065, 1.3),
    (1.02, 0.94, 0.55, 0.055, 2.4),
]
cowl_component_centers_y = []
for component, (scale_x, scale_y, scale_z, shift_z, phase) in zip(
    cowl_components, cowl_drape_settings
):
    coordinates = [clean_cowl.data.vertices[index].co.copy() for index in component]
    min_z = min(co.z for co in coordinates)
    max_z = max(co.z for co in coordinates)
    min_y = min(co.y for co in coordinates)
    max_y = max(co.y for co in coordinates)
    center_z = 0.5 * (min_z + max_z)
    center_y = 0.5 * (min_y + max_y)
    cowl_component_centers_y.append(center_y)
    radius_x = max(abs(co.x) for co in coordinates)
    radius_y = max(abs(co.y - center_y) for co in coordinates)
    for index in component:
        co = clean_cowl.data.vertices[index].co
        theta = math.atan2(
            (co.y - center_y) / max(1.0e-8, radius_y),
            co.x / max(1.0e-8, radius_x),
        )
        co.x *= scale_x
        co.y = center_y + (co.y - center_y) * scale_y
        co.z = (
            center_z
            + (co.z - center_z) * scale_z
            + shift_z
            + 0.006 * math.sin(3.0 * theta + phase)
            + 0.003 * math.sin(7.0 * theta - phase)
        )
        front_amount = max(
            0.0,
            min(
                1.0,
                -(co.y - center_y) / max(1.0e-8, radius_y * scale_y),
            ),
        )
        center_amount = max(
            0.0,
            1.0
            - max(
                0.0,
                min(1.0, (co.x / max(1.0e-8, radius_x * scale_x)) ** 2),
            ),
        )
        co.z -= 0.010 * front_amount * center_amount
# Preserve every layer's topology while clearing the MPFB neck.  If a layer
# intersects the head, expand that complete closed layer radially in tiny steps;
# unlike per-vertex clamping this cannot stretch or flip the inner-rim faces.
from mathutils.bvhtree import BVHTree

cowl_vertex_component = {}
for component_index, component in enumerate(cowl_components):
    for vertex_index in component:
        cowl_vertex_component[vertex_index] = component_index
cowl_face_component = [
    cowl_vertex_component[poly.vertices[0]] for poly in clean_cowl.data.polygons
]


def _v3_local_bvh(obj):
    return BVHTree.FromPolygons(
        [vertex.co.copy() for vertex in obj.data.vertices],
        [tuple(poly.vertices) for poly in obj.data.polygons],
        all_triangles=False,
        epsilon=1.0e-7,
    )


head_clearance_bvh = _v3_local_bvh(head)
cowl_clearance_iterations = [0, 0, 0]
for _clearance_step in range(48):
    clean_cowl.data.update()
    cowl_head_pairs = _v3_local_bvh(clean_cowl).overlap(head_clearance_bvh)
    if not cowl_head_pairs:
        break
    colliding_components = {
        cowl_face_component[cowl_face_index]
        for cowl_face_index, _head_face_index in cowl_head_pairs
    }
    for component_index in colliding_components:
        center_y = cowl_component_centers_y[component_index]
        for vertex_index in cowl_components[component_index]:
            co = clean_cowl.data.vertices[vertex_index].co
            co.x *= 1.004
            co.y = center_y + (co.y - center_y) * 1.004
        cowl_clearance_iterations[component_index] += 1
else:
    raise RuntimeError("Could not clear draped cowl from MPFB head without distortion")
clean_cowl.data.update()
clean_cowl["game_asset"] = True
clean_cowl["part_category"] = "ClothedBody"
clean_cowl["source"] = "Preserved v1 clean closed cowl, v3 drape"'''
source = replace_once(source, old_donor_cut, new_donor_cut, "unified donor head cut")

source = replace_once(
    source,
    '''fixed_triangles = triangle_count(head) + triangle_count(eyes) + sum(
    triangle_count(obj) for obj in eye_disks
)''',
    '''fixed_triangles = (
    triangle_count(head)
    + triangle_count(eyes)
    + triangle_count(clean_cowl)
    + sum(triangle_count(obj) for obj in eye_disks)
)''',
    "reserve triangle budget for clean cowl",
)

# Arm/sleeve classification must precede the head/cowl test.  Otherwise every
# upper sleeve side above z=1.50 becomes dark cowl and reads as a second wing.
old_side_material = '''def side_material_index(center, side_role):
    x, y, z = center
    ax = abs(x)
    if z > 1.50:
        if side_role == "head" and ax < 0.115 and y < -0.08:
            return 2  # only the MPFB front facial margin remains skin
        return 5  # donor hair/cowl and rear/upper MPFB scalp stay dark
    if z > 1.18 and ax > 0.24:
        if ax > 0.76:
            return 2  # exposed hands
        if ax > 0.50 and z < 1.44:
            return 6  # bracers
        return 3  # padded sleeves
    if z < 0.34:
        return 6  # wrapped leather boots
    if z < 1.08:
        return 4  # outer coat and skirt
    if z > 1.40:
        return 5  # cowl
    return 4  # torso outer wool'''
new_side_material = '''def side_material_index(center, side_role):
    x, y, z = center
    ax = abs(x)
    if z > 1.18 and ax > 0.21:
        if ax > 0.76:
            return 2  # exposed hands
        if ax > 0.50 and z < 1.46:
            return 6  # bracers
        return 3  # padded sleeves and shoulder caps
    if z > 1.50:
        if side_role == "head" and ax < 0.115 and y < -0.08:
            return 2  # MPFB facial margin
        return 5  # central scalp/cowl only
    if z < 0.34:
        return 6  # wrapped leather boots
    if z < 1.08:
        return 4  # outer coat and skirt
    if z > 1.40:
        return 5  # cowl
    return 4  # torso outer wool'''
source = replace_once(
    source, old_side_material, new_side_material, "upper-sleeve material priority"
)

# The clean cowl uses the reference front/back projection at a lower normal
# threshold so its broad folds retain the painted garment detail.  Its grazing
# faces always use the dedicated cowl PBR material.
source = replace_once(
    source,
    '''        local_threshold = (
            0.68
            if side_role == "donor" and center.z > 1.42
            else SIDE_NORMAL_THRESHOLD
        )''',
    '''        local_threshold = (
            0.24
            if side_role == "cowl"
            else (
                0.68
                if side_role == "donor" and center.z > 1.42
                else SIDE_NORMAL_THRESHOLD
            )
        )''',
    "cowl projection threshold",
)
source = replace_once(
    source,
    '''        else:
            poly.material_index = side_material_index(center, side_role)
            side_faces += 1''',
    '''        else:
            poly.material_index = (
                5 if side_role == "cowl" else side_material_index(center, side_role)
            )
            side_faces += 1''',
    "cowl side material",
)

source = replace_once(
    source,
    '''mat_cowl = make_pbr_material("MAT_CowlWool_Side_PBR_4K", "cowl_wool", 0.70)
mat_leather = make_pbr_material("MAT_Leather_Side_PBR_4K", "leather", 0.62)''',
	'''mat_cowl = make_pbr_material("MAT_CowlWool_Side_PBR_4K", "cowl_wool", 0.70)
mat_leather = make_pbr_material("MAT_Leather_Side_PBR_4K", "leather", 0.62)
set_smooth(clean_cowl)''',
    "assign v3 cowl material",
)

source = replace_once(
    source,
    '''    head.name: assign_projection_uv_and_materials(
        head, all_surface_materials, projection_x_bounds, projection_z_bounds, "head"
    ),
}''',
    '''    head.name: assign_projection_uv_and_materials(
        head, all_surface_materials, projection_x_bounds, projection_z_bounds, "head"
    ),
    clean_cowl.name: assign_projection_uv_and_materials(
        clean_cowl,
        all_surface_materials,
        projection_x_bounds,
        projection_z_bounds,
        "cowl",
    ),
}

# Remove the remaining dark donor cowl shards only after projection has assigned
# material index 5.  BMesh preserves the projected UV and material layers.
donor_shard_bm = bmesh.new()
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
    bmesh.ops.delete(donor_shard_bm, geom=donor_shard_faces, context="FACES")
# Head/cowl cuts can detach tiny hair or inner-shell islands.  Retain the one
# connected clothed body and remove every floating fragment before export.
remaining_faces = set(donor_shard_bm.faces)
donor_postcut_components = []
while remaining_faces:
    seed_face = remaining_faces.pop()
    component_faces = {seed_face}
    stack = [seed_face]
    while stack:
        face = stack.pop()
        for vertex in face.verts:
            for neighbor_face in vertex.link_faces:
                if neighbor_face in remaining_faces:
                    remaining_faces.remove(neighbor_face)
                    component_faces.add(neighbor_face)
                    stack.append(neighbor_face)
    donor_postcut_components.append(component_faces)
largest_postcut_component = max(donor_postcut_components, key=len)
donor_fragment_faces = [
    face
    for component_faces in donor_postcut_components
    if component_faces is not largest_postcut_component
    for face in component_faces
]
donor_postcut_fragment_triangles_removed = sum(
    max(1, len(face.verts) - 2) for face in donor_fragment_faces
)
if donor_fragment_faces:
    bmesh.ops.delete(donor_shard_bm, geom=donor_fragment_faces, context="FACES")
loose_vertices = [vertex for vertex in donor_shard_bm.verts if not vertex.link_faces]
if loose_vertices:
    bmesh.ops.delete(donor_shard_bm, geom=loose_vertices, context="VERTS")
donor_shard_bm.to_mesh(donor.data)
donor_shard_bm.free()
donor.data.update()
set_smooth(donor)
donor_face_triangles_removed += (
    donor_cowl_shard_triangles_removed
    + donor_postcut_fragment_triangles_removed
)
projection_counts[donor.name] = {
    "front": sum(poly.material_index == 0 for poly in donor.data.polygons),
    "back": sum(poly.material_index == 1 for poly in donor.data.polygons),
    "side": sum(poly.material_index not in {0, 1} for poly in donor.data.polygons),
}

# Arms, hands and boots looked like duplicate shells because hard per-face
# front/back projection changes remained visible around their curved silhouette.
# Geometry QA proves each limb is one shell, so keep every face and give each
# region one continuous 4K PBR material with dominant-axis box UVs.
limb_pbr_uv_scale = 6.0
limb_pbr_face_counts = {"sleeves": 0, "bracers": 0, "hands": 0, "boots": 0}
donor_uv = donor.data.uv_layers.get("UVMap")
if donor_uv is None:
    donor_uv = donor.data.uv_layers.new(name="UVMap")
for poly in donor.data.polygons:
    x, y, z = poly.center
    ax = abs(x)
    limb_role = None
    if z < 0.40:
        limb_role = "boots"
        poly.material_index = 6
    elif z > 1.18 and ax > 0.21:
        if ax > 0.76:
            limb_role = "hands"
            poly.material_index = 2
        elif ax > 0.50 and z < 1.46:
            limb_role = "bracers"
            poly.material_index = 6
        else:
            limb_role = "sleeves"
            poly.material_index = 3
    if limb_role is None:
        continue
    limb_pbr_face_counts[limb_role] += 1
    normal = poly.normal
    abs_normal = (abs(normal.x), abs(normal.y), abs(normal.z))
    for loop_index in poly.loop_indices:
        co = donor.data.vertices[donor.data.loops[loop_index].vertex_index].co
        if abs_normal[0] >= abs_normal[1] and abs_normal[0] >= abs_normal[2]:
            box_u, box_v = co.y, co.z
        elif abs_normal[1] >= abs_normal[2]:
            box_u, box_v = co.x, co.z
        else:
            box_u, box_v = co.x, co.y
        donor_uv.data[loop_index].uv = (
            box_u * limb_pbr_uv_scale,
            box_v * limb_pbr_uv_scale,
        )
donor.data.update()
limb_projection_faces_remaining = sum(
    poly.material_index in {0, 1}
    for poly in donor.data.polygons
    if (
        poly.center.z < 0.40
        or (poly.center.z > 1.18 and abs(poly.center.x) > 0.21)
    )
)
if limb_projection_faces_remaining:
    raise RuntimeError(
        "Hard front/back projection remains on %d limb faces"
        % limb_projection_faces_remaining
    )
donor["limb_material_mode"] = "continuous_4K_PBR_box_UV"
donor["limb_pbr_uv_scale"] = limb_pbr_uv_scale
projection_counts[donor.name] = {
    "front": sum(poly.material_index == 0 for poly in donor.data.polygons),
    "back": sum(poly.material_index == 1 for poly in donor.data.polygons),
    "side": sum(poly.material_index not in {0, 1} for poly in donor.data.polygons),
}''',
    "project draped cowl and remove donor shards",
)

source = replace_once(
    source,
    'character_meshes = [donor, head, eyes] + eye_disks',
    'character_meshes = [donor, head, eyes, clean_cowl] + eye_disks',
    "skin/export clean cowl",
)

# Keep the deterministic iris/pupil geometry, but make it narrow, subtle and
# recessed behind the projected eyelids instead of exposing large round discs.
source = replace_once(
    source,
    '    eye_disks.extend((iris, pupil))',
    '''    for disk in (iris, pupil):
        scale_x = 0.72 if disk == iris else 0.60
        scale_z = 0.55 if disk == iris else 0.50
        for vertex in disk.data.vertices:
            vertex.co.x = cx + (vertex.co.x - cx) * scale_x
            vertex.co.z = cz + (vertex.co.z - cz) * scale_z - 0.004
            vertex.co.y += 0.00010
        disk.data.update()
    eye_disks.extend((iris, pupil))''',
    "resize and recess iris and pupil disks",
)
source = replace_once(
    source,
    'make_simple_material("MAT_Eyes_WarmSclera", (0.22, 0.16, 0.12, 1.0), 0.30)',
    'make_simple_material("MAT_Eyes_WarmSclera", (0.06, 0.045, 0.035, 1.0), 0.42)',
    "shadowed neutral sclera",
)

# Save the editable Blender presentation with both armatures hidden. They are
# made visible again only in memory for GLB export, so users opening the blend
# see the character rather than 706 control/deform bones over the limbs.
source = replace_once(
    source,
    '''bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print("SAVED_BLEND", BLEND_PATH)''',
    '''rig.hide_viewport = True
rig.hide_set(True)
metarig.hide_viewport = True
metarig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print("SAVED_BLEND", BLEND_PATH)
rig.hide_viewport = False
rig.hide_set(False)''',
    "hide rig in saved Blender presentation",
)

# Add an exact triangle-level BVH collision assertion before any preview, save,
# or export.  This guards against future source changes that reintroduce overlap.
qa_anchor = '''# Neutral, low-specular studio preserving the reference projection's dark contrast.
scene.world.color = (0.008, 0.008, 0.010)'''
qa_injection = '''# Exact donor/head intersection QA before rendering or publishing.
from mathutils.bvhtree import BVHTree


def _v3_mesh_bvh(obj):
    return BVHTree.FromPolygons(
        [vertex.co.copy() for vertex in obj.data.vertices],
        [tuple(poly.vertices) for poly in obj.data.polygons],
        all_triangles=False,
        epsilon=1.0e-7,
    )


donor_headneck_overlap_pairs = len(_v3_mesh_bvh(donor).overlap(_v3_mesh_bvh(head)))
cowl_head_overlap_pairs = len(_v3_mesh_bvh(clean_cowl).overlap(_v3_mesh_bvh(head)))
cowl_donor_overlap_pairs = len(_v3_mesh_bvh(clean_cowl).overlap(_v3_mesh_bvh(donor)))
if donor_headneck_overlap_pairs or cowl_head_overlap_pairs or cowl_donor_overlap_pairs:
    raise RuntimeError(
        "V3 overlap remains donor/head=%d cowl/head=%d cowl/donor=%d"
        % (donor_headneck_overlap_pairs, cowl_head_overlap_pairs, cowl_donor_overlap_pairs)
    )


# Neutral, low-specular studio preserving the reference projection's dark contrast.
scene.world.color = (0.008, 0.008, 0.010)'''
source = replace_once(source, qa_anchor, qa_injection, "BVH overlap QA")

# Clear, independent v3 names for collections, rig, previews and summary.
renames = {
    "Mercenary_GameReady_v2": "Mercenary_GameReady_v3",
    "Preview_v2": "Preview_v3",
    "metarig_mercenary_v2": "metarig_mercenary_v3",
    "mercenary_v2_rig": "mercenary_v3_rig",
    "Mercenary_Rigify_Rig_v2": "Mercenary_Rigify_Rig_v3",
    "Mercenary_Rigify_Skeleton_v2": "Mercenary_Rigify_Skeleton_v3",
    "PREVIEW_v2_": "PREVIEW_v3_",
    "mercenary_game_ready_v2_": "mercenary_game_ready_v3_",
    '"asset": "mercenary_crossbowman_game_ready_v2"': '"asset": "mercenary_crossbowman_game_ready_v3"',
    'print("BUILD_SUMMARY_V2"': 'print("BUILD_SUMMARY_V3"',
}
for old, new in renames.items():
    source = source.replace(old, new)

# Record the geometric proof and the source-preservation contract in the v3
# summary while retaining all original production metadata expected by verifier.
summary_anchor = '''    "donor_front_face_triangles_removed": donor_face_triangles_removed,
    "donor_refine": "Catmull-Clark level 1 then dynamic collapse decimation",'''
summary_replacement = '''    "donor_front_face_triangles_removed": donor_face_triangles_removed,
    "donor_head_cut": {
        "method": "single smooth capsule boolean; legacy front cut removed",
        "z_range": [1.445, 1.820],
        "maximum_radius_x": 0.170,
        "maximum_radius_y": 0.190,
        "mpfb_head_z_gt": 1.49,
    },
    "donor_headneck_bvh_overlap_pairs": donor_headneck_overlap_pairs,
    "donor_headneck_geometry_overlap": "ZERO_CONFIRMED_BVH",
    "clean_cowl_head_bvh_overlap_pairs": cowl_head_overlap_pairs,
    "clean_cowl_donor_bvh_overlap_pairs": cowl_donor_overlap_pairs,
    "eyes": {
        "geometry": "curved MPFB eyeballs with resized recessed iris/pupil discs",
        "iris_horizontal_scale": 0.72,
        "iris_vertical_scale": 0.55,
        "pupil_horizontal_scale": 0.60,
        "pupil_vertical_scale": 0.50,
    },
    "limb_material_cleanup": {
        "mode": "continuous 4K PBR with dominant-axis box UVs",
        "uv_scale": limb_pbr_uv_scale,
        "face_counts": limb_pbr_face_counts,
        "front_back_projection_faces_remaining": limb_projection_faces_remaining,
        "geometry_shells_added_or_deleted": False,
    },
    "blender_presentation": {
        "rig_hidden_in_saved_blend": True,
        "metarig_hidden_in_saved_blend": True,
    },
    "donor_cowl_triangles_removed": donor_cowl_triangles_removed,
    "donor_cowl_shard_triangles_removed": donor_cowl_shard_triangles_removed,
    "donor_postcut_fragment_triangles_removed": donor_postcut_fragment_triangles_removed,
    "donor_postcut_component_face_counts": sorted(
        (len(component) for component in donor_postcut_components), reverse=True
    ),
    "clean_cowl_drape": {
        "components": 3,
        "projection": "reference front/back by actual world z; side cowl PBR",
        "normal_y_threshold": 0.24,
        "uniform_clearance_iterations": cowl_clearance_iterations,
    },
    "v2_source_preserved": os.path.join(
        STAGING_DIR, "mercenary_crossbowman_game_ready_v2.blend"
    ),
    "donor_refine": "Catmull-Clark level 1 then dynamic collapse decimation",'''
source = replace_once(source, summary_anchor, summary_replacement, "summary QA fields")

# Execute the transformed full authoring pipeline in this script's global scope.
compiled = compile(source, str(V2_SCRIPT) + " [v3 in-memory patch]", "exec")
exec(compiled, globals(), globals())
