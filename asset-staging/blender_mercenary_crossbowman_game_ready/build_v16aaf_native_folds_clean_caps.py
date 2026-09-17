"""Preserve the natural scanned scarf folds; seal only neck and shoulder gaps."""

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zm_clean_rear_shoulders.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16aaj_clean_draped_cowl.blend"
REPORT = STAGING / "v16aaj_clean_draped_cowl_report.json"
COWL_OLD = "Mercenary_SculptedLowerDrapeCowl_v16zl_LOD0"
COWL = "Mercenary_CleanDrapedScarf_v16aaj_LOD0"


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj):
    edge_counts = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            edge_counts[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        queue = deque([unseen.pop()])
        while queue:
            found = adjacency[queue.popleft()] & unseen
            unseen.difference_update(found)
            queue.extend(found)
    return {
        "components": components,
        "boundary_edges": sum(v == 1 for v in edge_counts.values()),
        "nonmanifold_edges": sum(v != 2 for v in edge_counts.values()),
        "overconnected_edges": sum(v > 2 for v in edge_counts.values()),
    }


def weight_samples(obj, minimum_z=None):
    names = {g.index: g.name for g in obj.vertex_groups}
    samples = []
    for vertex in obj.data.vertices:
        if minimum_z is not None and vertex.co.z < minimum_z:
            continue
        weights = {
            names[item.group]: item.weight
            for item in vertex.groups
            if item.group in names and item.weight > 1.0e-6
        }
        if weights:
            samples.append((vertex.co.copy(), weights))
    tree = KDTree(len(samples))
    for i, (co, _weights) in enumerate(samples):
        tree.insert(co, i)
    tree.balance()
    return samples, tree


def transfer_weights(obj, samples, tree):
    obj.vertex_groups.clear()
    groups = {}
    for vertex in obj.data.vertices:
        _co, sample_i, _dist = tree.find(vertex.co)
        ranked = sorted(samples[sample_i][1].items(), key=lambda item: item[1], reverse=True)[:4]
        total = sum(weight for _name, weight in ranked) or 1.0
        for name, weight in ranked:
            group = groups.get(name)
            if group is None:
                group = obj.vertex_groups.new(name=name)
                groups[name] = group
            group.add([vertex.index], weight / total, "REPLACE")


def rig_object(obj, rig):
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)
    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


def create_mesh(name, vertices, faces, uvs, material, collection):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.material_index = 0
        poly.use_smooth = True
        for loop_index in poly.loop_indices:
            vi = mesh.loops[loop_index].vertex_index
            uv_layer.data[loop_index].uv = uvs[vi]
    obj["game_asset"] = True
    obj["part_category"] = "ClothedBody"
    obj["intentional_layer"] = True
    return obj


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects[COWL_OLD]
collection = donor.users_collection[0]
cowl_samples, cowl_tree = weight_samples(cowl)

# Remove the earlier exaggerated cowl.  The already repaired torso, arms,
# detailed head, hair and generated Rigify rig remain untouched.
removed = []
for name in (
    COWL_OLD,
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
        removed.append(name)

# Build one continuous, closed cloth garment.  Several broad wrinkles live in
# the same surface, so there are no stacked torus layers or black slots.
cowl_material = bpy.data.materials.get("MAT_CowlTop_SelectiveCharcoal_PBR_4K")
if cowl_material is None:
    cowl_material = bpy.data.materials.get("MAT_CowlWool_Side_PBR_4K")
front_source = bpy.data.materials.get("MAT_ReferenceProjection_Front_4K")
back_source = bpy.data.materials.get("MAT_ReferenceProjection_Back_4K")


def projected_material(source, name):
    material = source.copy()
    material.name = name
    material.use_backface_culling = False
    if material.use_nodes:
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        uv_node = nodes.new("ShaderNodeUVMap")
        uv_node.name = "AAJ_ReferenceProjectionUV"
        uv_node.uv_map = "ReferenceProjection"
        for node in nodes:
            if node.type == "TEX_IMAGE":
                links.new(uv_node.outputs["UV"], node.inputs["Vector"])
    return material


front_material = projected_material(front_source, "MAT_v16aaj_ScarfReferenceFront_4K")
back_material = projected_material(back_source, "MAT_v16aaj_ScarfReferenceBack_4K")
SEG = 160
BANDS = 40
verts = []
faces = []
uvs = []

def angle_delta(value, centre):
    return (value - centre + math.pi) % math.tau - math.pi


def angular_lobe(value, centre, width):
    return math.exp(-0.5 * (angle_delta(value, centre) / width) ** 2)


def ridge(t, centre, width):
    # One soft compression fold and its shallow valley.  The angular masks
    # below prevent these from becoming complete concentric rings.
    crest = math.exp(-((t - centre) / width) ** 2)
    valley = math.exp(-((t - centre - width * 0.95) / (width * 0.82)) ** 2)
    return crest - 0.42 * valley


def cowl_surface(t, angle):
    ease = t * t * (3.0 - 2.0 * t)
    rear = max(0.0, math.sin(angle))
    front = max(0.0, -math.sin(angle))
    side = abs(math.cos(angle))
    left = max(0.0, -math.cos(angle))

    # A close neckline that relaxes into a compact shoulder scarf.  The back
    # carries more cloth while the front stays clear of the chest straps.
    inner_rx = 0.116 + 0.004 * math.sin(3.0 * angle + 0.35)
    inner_ry = 0.086 + 0.003 * math.sin(2.0 * angle - 0.55)
    outer_rx = 0.214 + 0.012 * rear + 0.006 * left + 0.004 * math.sin(3.0 * angle + 0.7)
    outer_ry = 0.142 + 0.040 * rear - 0.004 * front + 0.004 * math.sin(4.0 * angle - 0.2)
    rx = inner_rx * (1.0 - ease) + outer_rx * ease
    ry = inner_ry * (1.0 - ease) + outer_ry * ease

    inner_z = 1.585 - 0.020 * front + 0.025 * rear + 0.004 * math.sin(2.0 * angle + 0.2)
    outer_z = 1.405 - 0.026 * front - 0.037 * rear + 0.006 * side
    outer_z += 0.006 * math.sin(3.0 * angle + 0.9)
    z = inner_z * (1.0 - ease) + outer_z * ease

    # Four broad, wandering folds occupy different arcs of the same cloth.
    # Their low amplitudes read as drape instead of stacked rubber tubes.
    p1 = 0.18 + 0.060 * math.sin(angle + 0.45)
    p2 = 0.39 + 0.075 * math.sin(angle - 1.10) + 0.018 * math.sin(2.0 * angle)
    p3 = 0.61 + 0.070 * math.sin(angle + 1.55)
    p4 = 0.81 + 0.050 * math.sin(2.0 * angle - 0.65)
    f1 = ridge(t, p1, 0.080) * (0.10 + 0.90 * angular_lobe(angle, -0.50, 1.05))
    f2 = ridge(t, p2, 0.095) * (0.10 + 0.90 * angular_lobe(angle, 2.30, 1.10))
    f3 = ridge(t, p3, 0.105) * (0.08 + 0.92 * angular_lobe(angle, -2.05, 1.05))
    f4 = ridge(t, p4, 0.090) * (0.08 + 0.92 * angular_lobe(angle, 0.85, 1.15))
    relief = 0.012 * f1 + 0.015 * f2 + 0.014 * f3 + 0.011 * f4
    envelope = math.sin(math.pi * t) ** 1.15
    relief += envelope * (
        0.0025 * math.sin(3.0 * angle + 4.2 * t)
        + 0.0015 * math.sin(7.0 * angle - 5.5 * t)
    )
    rx += relief * (0.82 + 0.18 * side)
    ry += relief * (0.82 + 0.18 * (front + rear))
    z += 0.38 * relief + envelope * 0.003 * math.sin(angle - 2.8 * t)

    # Slight wrapped drift and a soft uneven hem remove the CAD symmetry.
    tangent = envelope * (0.0040 * math.sin(angle + 2.1 * t) + 0.0015 * math.sin(3.0 * angle - 1.7 * t))
    centre_x = -0.004 * ease
    centre_y = 0.010 + 0.011 * ease
    x = centre_x + rx * math.cos(angle) - tangent * math.sin(angle)
    y = centre_y + ry * math.sin(angle) + tangent * math.cos(angle)
    return (x, y, z)

for surface in (0, 1):
    for band in range(BANDS + 1):
        t = band / BANDS
        for seg in range(SEG):
            angle = math.tau * seg / SEG
            x, y, z = cowl_surface(t, angle)
            if surface == 1:
                # Six-millimetre closed wool thickness, mostly hidden below.
                scale = 1.0 - (0.0060 / max(0.09, math.hypot(x, y)))
                x *= scale
                y = 0.008 + (y - 0.008) * scale
                z -= 0.0025
            verts.append((x, y, z))
            uvs.append((seg / SEG * 3.0, t * 2.2))

ring_count = (BANDS + 1) * SEG
def ci(surface, band, seg):
    return surface * ring_count + band * SEG + seg % SEG

for surface in (0, 1):
    for band in range(BANDS):
        for seg in range(SEG):
            nxt = (seg + 1) % SEG
            quad = (ci(surface, band, seg), ci(surface, band + 1, seg), ci(surface, band + 1, nxt), ci(surface, band, nxt))
            faces.append(quad if surface == 0 else tuple(reversed(quad)))
for band in (0, BANDS):
    for seg in range(SEG):
        nxt = (seg + 1) % SEG
        if band == 0:
            faces.append((ci(0, band, nxt), ci(0, band, seg), ci(1, band, seg), ci(1, band, nxt)))
        else:
            faces.append((ci(0, band, seg), ci(0, band, nxt), ci(1, band, nxt), ci(1, band, seg)))

cowl = create_mesh(COWL, verts, faces, uvs, cowl_material, collection)
cowl.data.materials.clear()

# One material smoothly cross-fades the front and rear 4K reference plates
# around the sides.  This removes the hard vertical seam/black islands that
# appeared when the two images were assigned to separate face groups.
blend_material = bpy.data.materials.new("MAT_v16aaj_SeamlessScarfProjection_4K")
blend_material.use_nodes = True
blend_material.use_backface_culling = False
nodes = blend_material.node_tree.nodes
links = blend_material.node_tree.links
nodes.clear()
output_node = nodes.new("ShaderNodeOutputMaterial")
bsdf_node = nodes.new("ShaderNodeBsdfPrincipled")
bsdf_node.inputs["Roughness"].default_value = 0.78
front_tex = nodes.new("ShaderNodeTexImage")
front_tex.name = "ScarfReferenceFront_4K"
front_tex.image = next(node.image for node in front_source.node_tree.nodes if node.type == "TEX_IMAGE" and node.image)
back_tex = nodes.new("ShaderNodeTexImage")
back_tex.name = "ScarfReferenceBack_4K"
back_tex.image = next(node.image for node in back_source.node_tree.nodes if node.type == "TEX_IMAGE" and node.image)
front_uv_node = nodes.new("ShaderNodeUVMap")
front_uv_node.uv_map = "FrontProjection"
back_uv_node = nodes.new("ShaderNodeUVMap")
back_uv_node.uv_map = "BackProjection"
blend_attribute = nodes.new("ShaderNodeAttribute")
blend_attribute.attribute_name = "ProjectionBlend"
blend_node = nodes.new("ShaderNodeMixRGB")
blend_node.blend_type = "MIX"
links.new(front_uv_node.outputs["UV"], front_tex.inputs["Vector"])
links.new(back_uv_node.outputs["UV"], back_tex.inputs["Vector"])
links.new(blend_attribute.outputs["Fac"], blend_node.inputs[0])
links.new(front_tex.outputs["Color"], blend_node.inputs[1])
links.new(back_tex.outputs["Color"], blend_node.inputs[2])
links.new(blend_node.outputs["Color"], bsdf_node.inputs["Base Color"])
links.new(bsdf_node.outputs["BSDF"], output_node.inputs["Surface"])

# Retain the proper wool normal detail independently of the photographic
# colour projection, using the tiled garment UVs.
normal_source = next(
    (node for node in cowl_material.node_tree.nodes
     if node.type == "TEX_IMAGE" and node.image and "normal" in node.image.name.lower()),
    None,
)
if normal_source is not None:
    wool_uv_node = nodes.new("ShaderNodeUVMap")
    wool_uv_node.uv_map = "UVMap"
    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.name = "ScarfWoolNormal_4K"
    normal_tex.image = normal_source.image
    normal_tex.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.62
    links.new(wool_uv_node.outputs["UV"], normal_tex.inputs["Vector"])
    links.new(normal_tex.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf_node.inputs["Normal"])

cowl.data.materials.append(blend_material)
front_uv = cowl.data.uv_layers.new(name="FrontProjection")
back_uv = cowl.data.uv_layers.new(name="BackProjection")
for poly in cowl.data.polygons:
    poly.material_index = 0
    for loop_index in poly.loop_indices:
        vertex = cowl.data.vertices[cowl.data.loops[loop_index].vertex_index]
        nx = (vertex.co.x + 0.83705318) / (2.0 * 0.83705318)
        nz = vertex.co.z / 1.78
        front_uv.data[loop_index].uv = (
            0.897705078125 - 0.7958984375 * nx,
            0.0576171875 + 0.883544921875 * nz,
        )
        back_uv.data[loop_index].uv = (
            0.9130859375 - 0.82568359375 * nx,
            0.05908203125 + 0.882568359375 * nz,
        )

blend_attr = cowl.data.attributes.new(name="ProjectionBlend", type="FLOAT", domain="POINT")
for vertex in cowl.data.vertices:
    angle = math.atan2(vertex.co.y - 0.015, vertex.co.x + 0.004)
    raw = 0.5 + 0.5 * math.sin(angle)
    blend_attr.data[vertex.index].value = raw * raw * (3.0 - 2.0 * raw)
transfer_weights(cowl, cowl_samples, cowl_tree)
rig_object(cowl, rig)
cowl["source"] = "V16AAJ compact single-piece asymmetrically draped wool scarf"
cowl["separate_cowl_rings"] = 0

checks = {}
for obj, expected_components in ((cowl, 1),):
    stats = topology(obj)
    weights = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    if stats["components"] != expected_components or stats["nonmanifold_edges"] != 0:
        raise RuntimeError(f"Topology failed: {obj.name}: {stats}")
    if min(weights) < 0.999 or max(weights) > 1.001:
        raise RuntimeError(f"Weights failed: {obj.name}: {min(weights)}..{max(weights)}")
    checks[obj.name] = {
        "triangles": triangles(obj), "topology": stats,
        "weight_sum_range": [min(weights), max(weights)],
    }

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or obj.name.startswith("PREVIEW_"):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.025, 0.028, 0.034, 1.0)
        bg.inputs[1].default_value = 0.14

lights = []
for name, location, energy, size, color in (
    ("V16AAF_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16AAF_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16AAF_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    lights.append(light)

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)
def render(key, location, target, lens=86, size=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = size
    path = PREVIEWS / f"diagnostic_v16aaj_clean_draped_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)

previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.49)),
    "high": render("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46)),
    "three_quarter": render("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}
for light in lights:
    data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if data.users == 0:
        bpy.data.lights.remove(data)

meshes = [obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None and not obj.name.startswith(("WGT-", "PREVIEW_"))]
total = sum(triangles(obj) for obj in meshes)
if not 100000 <= total <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total}")
report = {
    "source": str(SOURCE), "candidate": str(OUTPUT), "production_modified": False,
    "removed": removed, "checks": checks, "mesh_count": len(meshes),
    "total_triangles": total, "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "previews": previews,
}
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16AAI_REPORT=" + json.dumps(report, sort_keys=True))
