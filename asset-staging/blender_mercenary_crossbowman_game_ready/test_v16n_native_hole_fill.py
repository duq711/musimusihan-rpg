"""Fuse only the original sculpted scarf folds at high voxel resolution."""

from collections import defaultdict
import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16ad_fused_original_folds_candidate.blend"
REPORT = STAGING / "v16ad_fused_original_folds_report.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]

removed = []
for name in (
    "Mercenary_InnerCowl_RolledCollar_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_Liner_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        removed.append(name)
        bpy.data.objects.remove(obj, do_unlink=True)

source_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
material = source_material.copy()
material.name = "MAT_Cowl_FusedOriginalFolds_PBR_4K_v16ad"
material.use_backface_culling = False
nodes = material.node_tree.nodes
links = material.node_tree.links
texture = nodes.get("BaseColor_4K")
principled = nodes.get("Principled BSDF")
if texture is not None and principled is not None:
    for link in list(principled.inputs["Base Color"].links):
        links.remove(link)
    tone = nodes.new("ShaderNodeHueSaturation")
    tone.name = "FusedSculptedCharcoalTone_v16w"
    tone.inputs["Saturation"].default_value = 0.82
    tone.inputs["Value"].default_value = 0.52
    links.new(texture.outputs["Color"], tone.inputs["Color"])
    links.new(tone.outputs["Color"], principled.inputs["Base Color"])

recolored = []
for name in ("Mercenary_Cowl_LayeredClean_LOD0",):
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
    recolored.append(name)

# Move the nested original folds into slight contact, then voxel-union them at
# high resolution.  Their sculpted photographic silhouette is retained while
# the gaps and separate-shell overlap are removed.
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
bm = bmesh.new()
bm.from_mesh(cowl.data)
unseen = set(bm.verts)
components_before = []
while unseen:
    seed = unseen.pop()
    component = {seed}
    stack = [seed]
    while stack:
        vertex = stack.pop()
        linked = {edge.other_vert(vertex) for edge in vertex.link_edges} & unseen
        unseen.difference_update(linked)
        component.update(linked)
        stack.extend(linked)
    components_before.append(component)
components_before.sort(key=lambda group: max(abs(vertex.co.x) for vertex in group))
for index, component in enumerate(components_before):
    radial_scale = (1.15, 1.075, 1.0)[index]
    z_shift = (-0.032, -0.014, 0.0)[index]
    for vertex in component:
        vertex.co.x *= radial_scale
        vertex.co.y *= radial_scale
        vertex.co.z += z_shift
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()
cowl.name = "Mercenary_FusedOriginalFoldsCowl_LOD0"
cowl.data.name = "Mercenary_FusedOriginalFoldsCowl_LOD0_Mesh"

# Remove skin modifiers before the topology rebuild; weights and the Rigify
# modifier are reconstructed below from the measured upper-body blend.
for modifier in list(cowl.modifiers):
    cowl.modifiers.remove(modifier)
cowl.data.remesh_voxel_size = 0.006
cowl.data.remesh_voxel_adaptivity = 0.0
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = cowl
cowl.select_set(True)
bpy.ops.object.voxel_remesh()

bm = bmesh.new()
bm.from_mesh(cowl.data)
for _ in range(1):
    bmesh.ops.smooth_vert(
        bm, verts=list(bm.verts), factor=0.08,
        use_axis_x=True, use_axis_y=True, use_axis_z=True,
    )
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()

cowl.data.materials.clear()
cowl.data.materials.append(material)
for polygon in cowl.data.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

for group in list(cowl.vertex_groups):
    cowl.vertex_groups.remove(group)

def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)

spine_4 = cowl.vertex_groups.new(name="DEF-spine.004")
spine_5 = cowl.vertex_groups.new(name="DEF-spine.005")
spine_6 = cowl.vertex_groups.new(name="DEF-spine.006")
arm_l = cowl.vertex_groups.new(name="DEF-upper_arm.L")
arm_r = cowl.vertex_groups.new(name="DEF-upper_arm.R")
for vertex in cowl.data.vertices:
    x, _y, z = vertex.co
    head = smoothstep((z - 1.49) / 0.085)
    arm = 0.27 * smoothstep((abs(x) - 0.235) / 0.11) * (1.0 - head)
    torso = max(0.0, 1.0 - head - arm)
    chest = torso * 0.39
    upper = torso - chest
    if chest:
        spine_4.add([vertex.index], chest, "REPLACE")
    if upper:
        spine_5.add([vertex.index], upper, "REPLACE")
    if head:
        spine_6.add([vertex.index], head, "REPLACE")
    if arm:
        (arm_l if x >= 0.0 else arm_r).add([vertex.index], arm, "REPLACE")
modifier = cowl.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["intentional_layer"] = True
cowl["source"] = "V16 high-resolution voxel union of the original sculpted folds"

bpy.context.view_layer.objects.active = cowl
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
bpy.ops.object.mode_set(mode="OBJECT")


def triangle_count(obj):
    return sum(max(1, len(face.vertices) - 2) for face in obj.data.polygons)


def component_count(obj):
    adjacency = defaultdict(set)
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    count = 0
    while unseen:
        count += 1
        stack = [unseen.pop()]
        while stack:
            current = stack.pop()
            linked = adjacency[current] & unseen
            unseen.difference_update(linked)
            stack.extend(linked)
    return count


def manifold_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for first, second in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return {
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_render = True
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
previews = {}


def render(key, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16ad_fused_original_folds_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    previews[key] = str(path)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("failure_view", (0.57, -0.57, 5.58), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("upper_three_quarter", (1.15, -1.55, 2.05), (0.0, 0.0, 1.49), lens=76, resolution=(1200, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
triangles = sum(triangle_count(obj) for obj in character_meshes)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in cowl.data.vertices]
topology = manifold_stats(cowl)
components = component_count(cowl)
if topology["nonmanifold_edges"] or components > 5:
    raise RuntimeError(f"Fused cowl topology failed: {topology}, components={components}")
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Fused cowl weights failed: {(min(weight_sums), max(weight_sums))}")
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "removed": removed,
    "fused_sources": recolored,
    "voxel_size": cowl.data.remesh_voxel_size,
    "fused_cowl_triangles": triangle_count(cowl),
    "fused_cowl_components": components,
    "fused_cowl_manifold": topology,
    "fused_cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "character_meshes": len(character_meshes),
    "character_triangles": triangles,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "previews": previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print(json.dumps(report, indent=2))
