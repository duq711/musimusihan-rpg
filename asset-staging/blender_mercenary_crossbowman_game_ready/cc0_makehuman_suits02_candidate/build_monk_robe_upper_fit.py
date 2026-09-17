"""Create a clean CC0 upper-garment candidate from Donitz' Monk's Robe.

The source asset is a male MakeHuman T-pose garment. This script keeps its
upper torso and both authored sleeves, fits them to the v16aaj proportions,
removes the temporary rectangular sleeves, and preserves the scarf separately.
"""

from pathlib import Path
import json
import math

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
CANDIDATE = STAGING / "cc0_makehuman_suits02_candidate"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16aaj_baked_cowl_candidate.blend"
OBJ = CANDIDATE / "clothes" / "donitz_monk_robe" / "Monks_Robe.obj"
DIFFUSE = CANDIDATE / "clothes" / "donitz_monk_robe" / "robe_brown__diffuse.png"
NORMAL = CANDIDATE / "clothes" / "donitz_monk_robe" / "robe__normal_gl.png"
LICENSE_META = CANDIDATE / "clothes" / "donitz_monk_robe" / "donitz_monk_robe.mhclo"
PACK_META = CANDIDATE / "packs" / "suits02.json"
OUTPUT = CANDIDATE / "mercenary_v16aaj_cc0_monk_robe_clean_upper_v6_candidate.blend"
REPORT = CANDIDATE / "mercenary_v16aaj_cc0_monk_robe_clean_upper_v6_report.json"
PREVIEWS = CANDIDATE / "previews"


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def create_material(name, saturation, value, tint_color):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    albedo = nodes.new("ShaderNodeTexImage")
    albedo.image = bpy.data.images.load(str(DIFFUSE), check_existing=True)
    albedo.image.colorspace_settings.name = "sRGB"
    grade = nodes.new("ShaderNodeHueSaturation")
    grade.inputs["Saturation"].default_value = saturation
    grade.inputs["Value"].default_value = value
    tint = nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 1.0
    tint.inputs[2].default_value = (*tint_color, 1.0)
    normal = nodes.new("ShaderNodeTexImage")
    normal.image = bpy.data.images.load(str(NORMAL), check_existing=True)
    normal.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.62
    bsdf.inputs["Roughness"].default_value = 0.86
    bsdf.inputs["Specular IOR Level"].default_value = 0.20

    links.new(albedo.outputs["Color"], grade.inputs["Color"])
    links.new(grade.outputs["Color"], tint.inputs[1])
    links.new(tint.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def isolate_and_fit_upper_and_sleeves(obj):
    """Keep the torso top and both real sleeves, excluding the shoulder cape.

    The MakeHuman robe sleeves were authored in a steep A-pose.  They are
    flattened around a fitted centerline here so that their cloth volume—not
    a procedural cylinder—follows the target T-pose arms.
    """
    mesh = obj.data
    adjacency = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)

    unseen = set(range(len(mesh.vertices)))
    components = []
    while unseen:
        start = unseen.pop()
        stack = [start]
        found = {start}
        while stack:
            current = stack.pop()
            for neighbor in adjacency[current]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    found.add(neighbor)
                    stack.append(neighbor)
        components.append(found)

    components.sort(key=len, reverse=True)
    body_vertices = components[0]
    sleeve_components = [
        component
        for component in components
        if 700 <= len(component) <= 900
        and max(abs(mesh.vertices[index].co.x) for index in component) > 4.7
    ]
    if len(sleeve_components) != 2:
        raise RuntimeError(f"Expected two authored sleeves, found {len(sleeve_components)}")
    sleeve_vertices = set().union(*sleeve_components)

    # Transform while source indices and Y-up coordinates are still intact.
    for vertex in mesh.vertices:
        x, y, z = vertex.co
        if vertex.index in sleeve_vertices:
            ax = abs(x)
            sleeve_center_y = 6.8762 - 0.9493 * ax
            sleeve_center_z = 0.6015 * ax - 1.2307
            radial_height = y - sleeve_center_y
            radial_depth = z - sleeve_center_z
            arm_t = min(1.0, max(0.0, (ax - 1.275) / (5.1686 - 1.275)))
            fitted_ax = 0.190 + arm_t * 0.660
            target_x = math.copysign(fitted_ax, x)
            target_y = 0.040 + radial_depth * 0.087
            target_z = 1.410 - 0.060 * arm_t + radial_height * 0.074
        else:
            target_x = x * 0.102
            # The upper torso is an under-layer.  Keeping it inside the
            # existing vest lets it show only through genuine donor gaps.
            target_y = z * 0.060 + 0.035
            target_z = y * 0.100 + 0.820
        vertex.co = (target_x, target_y, target_z)

    bm = bmesh.new()
    bm.from_mesh(mesh)
    delete_faces = []
    for face in bm.faces:
        source_indices = {vertex.index for vertex in face.verts}
        is_sleeve = source_indices.issubset(sleeve_vertices)
        is_body = source_indices.issubset(body_vertices)
        # Body is already transformed, so the crop is expressed in target Z.
        center_z = sum(vertex.co.z for vertex in face.verts) / len(face.verts)
        if is_sleeve:
            face.material_index = 0
        elif is_body and center_z >= 1.240:
            face.material_index = 1
        else:
            delete_faces.append(face)
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)


def add_rigify_weights(obj, rig):
    names = (
        "DEF-spine.003",
        "DEF-spine.004",
        "DEF-shoulder.L",
        "DEF-upper_arm.L",
        "DEF-upper_arm.L.001",
        "DEF-forearm.L",
        "DEF-forearm.L.001",
        "DEF-shoulder.R",
        "DEF-upper_arm.R",
        "DEF-upper_arm.R.001",
        "DEF-forearm.R",
        "DEF-forearm.R.001",
    )
    groups = {name: obj.vertex_groups.new(name=name) for name in names}

    for vertex in obj.data.vertices:
        x = vertex.co.x
        ax = abs(x)
        weights = {}
        if ax <= 0.18:
            chest = min(1.0, max(0.0, (vertex.co.z - 1.18) / 0.25))
            weights["DEF-spine.003"] = 1.0 - chest
            weights["DEF-spine.004"] = chest
        else:
            side = ".L" if x > 0.0 else ".R"
            if ax < 0.27:
                t = (ax - 0.18) / 0.09
                weights["DEF-spine.004"] = 0.45 * (1.0 - t)
                weights[f"DEF-shoulder{side}"] = 0.55 * (1.0 - t) + 0.25 * t
                weights[f"DEF-upper_arm{side}"] = 0.75 * t
            elif ax < 0.42:
                t = (ax - 0.27) / 0.15
                weights[f"DEF-upper_arm{side}"] = 1.0 - 0.55 * t
                weights[f"DEF-upper_arm{side}.001"] = 0.55 * t
            elif ax < 0.56:
                t = (ax - 0.42) / 0.14
                weights[f"DEF-upper_arm{side}.001"] = 1.0 - 0.70 * t
                weights[f"DEF-forearm{side}"] = 0.70 * t
            else:
                t = min(1.0, (ax - 0.56) / 0.11)
                weights[f"DEF-forearm{side}"] = 1.0 - 0.70 * t
                weights[f"DEF-forearm{side}.001"] = 0.70 * t

        total = sum(weights.values())
        for name, weight in weights.items():
            groups[name].add([vertex.index], weight / total, "REPLACE")

    obj.parent = rig
    modifier = obj.modifiers.new("Mercenary_Rigify_Deform", "ARMATURE")
    modifier.object = rig


def mesh_triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def remove_donor_arm_fragments(obj):
    """Delete only the broken T-pose arm shell that the new sleeves replace."""
    before = mesh_triangles(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    delete_faces = []
    for face in bm.faces:
        center = face.calc_center_median()
        ax = abs(center.x)
        if 0.175 < ax < 0.790 and 1.165 < center.z < 1.575:
            delete_faces.append(face)
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return before - mesh_triangles(obj)


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene

donor = bpy.data.objects.get("Mercenary_Clothed_Donor_LOD0")
if not donor:
    raise RuntimeError("Clothed donor mesh not found")
removed_donor_triangles = remove_donor_arm_fragments(donor)

removed = []
for name in (
    "Mercenary_GambesonUpperSleeves_v16zb_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj:
        removed.append(name)
        bpy.data.objects.remove(obj, do_unlink=True)

bpy.ops.object.select_all(action="DESELECT")
bpy.ops.wm.obj_import(filepath=str(OBJ))
upper = bpy.context.active_object
upper.name = "Mercenary_CC0_MonkRobe_CleanUpper_LOD0"
isolate_and_fit_upper_and_sleeves(upper)
upper.data.materials.clear()
upper.data.materials.append(
    create_material("CC0_Monk_Robe_Worn_Wool_Sleeves", 0.52, 1.45, (0.92, 0.84, 0.72))
)
upper.data.materials.append(
    create_material("CC0_Monk_Robe_Dark_Underlayer", 0.24, 0.92, (0.46, 0.50, 0.52))
)
for polygon in upper.data.polygons:
    polygon.use_smooth = True

bevel = upper.modifiers.new("Soft_Woven_Edges", "BEVEL")
bevel.width = 0.0014
bevel.segments = 2
bevel.limit_method = "ANGLE"
bevel.angle_limit = math.radians(48.0)

rig = bpy.data.objects.get("Mercenary_Rigify_Rig_v4")
if not rig:
    raise RuntimeError("Rigify deform rig not found")
add_rigify_weights(upper, rig)

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or obj.name.startswith("PREVIEW_"):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.render.resolution_x = 1200
scene.render.resolution_y = 1000
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.025, 0.028, 0.034, 1.0)
        background.inputs[1].default_value = 0.22

for name, location, energy, size, color in (
    ("CC0Upper_Key", (-2.2, -2.6, 3.3), 330.0, 2.5, (1.0, 0.82, 0.68)),
    ("CC0Upper_Fill", (2.4, -1.5, 2.5), 180.0, 2.2, (0.62, 0.76, 1.0)),
    ("CC0Upper_Rim", (0.3, 2.4, 2.7), 230.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))

PREVIEWS.mkdir(parents=True, exist_ok=True)
camera = scene.camera
preview_paths = {}
for key, location, target, lens in (
    ("top", (0.0, -0.01, 4.2), (0.0, 0.02, 1.12), 70),
    ("high", (0.92, -1.65, 2.38), (0.0, 0.015, 1.33), 70),
    ("three_quarter", (1.16, -2.20, 1.72), (0.0, 0.0, 1.08), 72),
    ("front", (0.0, -4.0, 1.05), (0.0, 0.0, 0.93), 70),
    ("back", (0.0, 4.0, 1.05), (0.0, 0.0, 0.93), 70),
):
    camera.data.type = "ORTHO" if key in {"top", "front", "back"} else "PERSP"
    camera.data.lens = lens
    if camera.data.type == "ORTHO":
        camera.data.ortho_scale = 2.15
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_y = 1200 if key in {"front", "back"} else 1000
    path = PREVIEWS / f"cc0_monk_robe_clean_upper_v6_{key}.png"
    preview_paths[key] = str(path)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)

# Count only visible production meshes, excluding controls and ground.
visible_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH"
    and not obj.hide_render
    and not obj.name.startswith("WGT-")
    and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(mesh_triangles(obj) for obj in visible_meshes)
deform_bones = len([bone for bone in rig.data.bones if bone.name.startswith("DEF-")])

report = {
    "candidate": str(OUTPUT),
    "source": str(SOURCE),
    "cc0_asset": str(OBJ),
    "license_header": str(LICENSE_META),
    "pack_metadata": str(PACK_META),
    "official_pack_url": "https://static.makehumancommunity.org/assets/assetpacks/suits02.html",
    "removed": removed,
    "removed_donor_triangles": removed_donor_triangles,
    "upper_vertices": len(upper.data.vertices),
    "upper_polygons": len(upper.data.polygons),
    "upper_triangles": mesh_triangles(upper),
    "total_triangles": total_triangles,
    "deform_bones": deform_bones,
    "preview_paths": preview_paths,
    "production_modified": False,
}
REPORT.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print(json.dumps(report, indent=2, ensure_ascii=False))
