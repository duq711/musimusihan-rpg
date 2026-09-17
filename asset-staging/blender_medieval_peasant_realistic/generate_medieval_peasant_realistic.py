import bpy
import math
import os
from mathutils import Vector


STAGING_DIR = "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_medieval_peasant"
STAGING_DIR = os.path.join(os.path.dirname(STAGING_DIR), "blender_medieval_peasant_realistic")
PREVIEW_DIR = os.path.join(STAGING_DIR, "previews")
BLEND_PATH = os.path.join(STAGING_DIR, "medieval_peasant_realistic_3d.blend")
GLB_PATH = "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/3d/dark_fantasy/medieval_peasant_3d.glb"

GLB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(STAGING_DIR)),
    "godot-game", "assets", "3d", "dark_fantasy", "medieval_peasant_realistic_3d.glb",
)

os.makedirs(PREVIEW_DIR, exist_ok=True)
os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)


def srgb_channel_to_linear(value):
    value = value / 255.0
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def color_from_hex(hex_color, alpha=1.0):
    value = hex_color.lstrip("#")
    return (
        srgb_channel_to_linear(int(value[0:2], 16)),
        srgb_channel_to_linear(int(value[2:4], 16)),
        srgb_channel_to_linear(int(value[4:6], 16)),
        alpha,
    )


def make_material(
    name,
    hex_color,
    roughness,
    metallic=0.0,
    specular_ior_level=0.32,
    subsurface_weight=0.0,
):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    rgba = color_from_hex(hex_color)
    material.diffuse_color = rgba
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular_ior_level
    if "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = subsurface_weight
    if subsurface_weight > 0.0 and "Subsurface Radius" in bsdf.inputs:
        bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.45, 0.22)
    return material


def move_to_collection(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def assign_material(obj, material):
    if hasattr(obj.data, "materials"):
        obj.data.materials.clear()
        obj.data.materials.append(material)


def parent_keep_world(obj, parent):
    bpy.context.view_layer.update()
    world_matrix = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world_matrix


def tag_part(obj, category):
    obj["part_category"] = category
    obj["game_asset"] = True


def make_empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.045
    obj.location = location
    asset_collection.objects.link(obj)
    if parent is not None:
        parent_keep_world(obj, parent)
    return obj


def make_ellipsoid(name, location, scale, material, parent=None, subdivisions=2, category="Body"):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    assign_material(obj, material)
    move_to_collection(obj, asset_collection)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, category)
    return obj


def make_ellipsoid_aligned(name, location, scale, direction, material, parent=None, category="Body"):
    obj = make_ellipsoid(name, location, scale, material, parent, subdivisions=2, category=category)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector(direction).to_track_quat("Z", "Y")
    return obj


def make_cone_between(name, point_a, point_b, radius_a, radius_b, material, parent=None,
                      vertices=16, smooth=True, category="Body", cap_ends=True):
    point_a = Vector(point_a)
    point_b = Vector(point_b)
    direction = point_b - point_a
    length = direction.length
    midpoint = (point_a + point_b) * 0.5
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_a,
        radius2=radius_b,
        depth=length,
        end_fill_type="NGON" if cap_ends else "NOTHING",
        location=midpoint,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = len(polygon.vertices) == 4
    assign_material(obj, material)
    move_to_collection(obj, asset_collection)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, category)
    return obj


def make_profile_limb(
    name,
    points,
    radii,
    material,
    parent=None,
    segments=18,
    category="Body",
    cap_ends=True,
):
    points = [Vector(point) for point in points]
    vertices = []
    for point_index, point in enumerate(points):
        if point_index == 0:
            tangent = (points[1] - points[0]).normalized()
        elif point_index == len(points) - 1:
            tangent = (points[-1] - points[-2]).normalized()
        else:
            tangent = (points[point_index + 1] - points[point_index - 1]).normalized()
        reference = Vector((0.0, 1.0, 0.0))
        if abs(tangent.dot(reference)) > 0.92:
            reference = Vector((1.0, 0.0, 0.0))
        axis_a = reference.cross(tangent).normalized()
        axis_b = tangent.cross(axis_a).normalized()
        radius_a, radius_b = radii[point_index]
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append(
                point
                + axis_a * (math.cos(angle) * radius_a)
                + axis_b * (math.sin(angle) * radius_b)
            )

    faces = []
    for point_index in range(len(points) - 1):
        lower = point_index * segments
        upper = (point_index + 1) * segments
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((lower + index, lower + next_index, upper + next_index, upper + index))
    if cap_ends:
        faces.append(tuple(reversed(range(segments))))
        final_start = (len(points) - 1) * segments
        faces.append(tuple(final_start + index for index in range(segments)))

    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    side_face_count = (len(points) - 1) * segments
    for polygon in obj.data.polygons[:side_face_count]:
        polygon.use_smooth = True
    assign_material(obj, material)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, category)
    return obj


def make_box(name, location, dimensions, material, parent=None, rotation=(0.0, 0.0, 0.0),
             bevel=0.0, category="Cloth", collection=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftenedEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    assign_material(obj, material)
    move_to_collection(obj, collection or asset_collection)
    if parent is not None:
        parent_keep_world(obj, parent)
    if (collection or asset_collection) == asset_collection:
        tag_part(obj, category)
    return obj


def make_oval_rings(
    name,
    rings,
    segments,
    material,
    parent=None,
    bottom_jitter=None,
    smooth=False,
    category="Cloth",
    fold_strength=0.0,
    cap_bottom=True,
    cap_top=True,
):
    vertices = []
    for ring_index, ring in enumerate(rings):
        z_pos, radius_x, radius_y = ring[:3]
        center_x = ring[3] if len(ring) > 3 else 0.0
        center_y = ring[4] if len(ring) > 4 else 0.0
        for index in range(segments):
            angle = (math.tau * index / segments) + (math.pi / segments)
            jitter = 0.0
            if ring_index == 0 and bottom_jitter:
                jitter = bottom_jitter[index % len(bottom_jitter)]
            lower_weight = 1.0 - (ring_index / max(1, len(rings) - 1))
            fold = 1.0 + fold_strength * (0.30 + 0.70 * lower_weight) * (
                0.62 * math.sin(6.0 * angle + 0.35)
                + 0.38 * math.sin(10.0 * angle - 0.20)
            )
            vertices.append((
                center_x + math.cos(angle) * radius_x * fold,
                center_y + math.sin(angle) * radius_y * fold,
                z_pos + jitter,
            ))

    faces = []
    for ring_index in range(len(rings) - 1):
        lower = ring_index * segments
        upper = (ring_index + 1) * segments
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((
                lower + index,
                lower + next_index,
                upper + next_index,
                upper + index,
            ))
    if cap_bottom:
        faces.append(tuple(reversed(range(segments))))
    top_start = (len(rings) - 1) * segments
    if cap_top:
        faces.append(tuple(top_start + index for index in range(segments)))

    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    if smooth:
        side_face_count = (len(rings) - 1) * segments
        for polygon in obj.data.polygons[:side_face_count]:
            polygon.use_smooth = True
    assign_material(obj, material)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, category)
    return obj


def make_triangle_patch(name, points, material, parent=None, category="Cloth"):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(points, [], [(0, 1, 2)])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, category)
    return obj


def make_hair_cap(
    name,
    center,
    material,
    parent=None,
    radius_x=0.084,
    radius_y=0.096,
    height=0.125,
):
    center = Vector(center)
    segments = 20
    angles = [18.0, 38.0, 58.0, 76.0, 92.0, 106.0]
    vertices = [(center.x, center.y, center.z + height)]
    for ring_index, angle_degrees in enumerate(angles):
        polar = math.radians(angle_degrees)
        ring_radius_x = math.sin(polar) * radius_x
        ring_radius_y = math.sin(polar) * radius_y
        z_pos = center.z + math.cos(polar) * height
        for index in range(segments):
            angle = math.tau * index / segments
            z_jitter = 0.0
            if ring_index == len(angles) - 1:
                # Higher forehead, lower rear hairline and small irregular clumps.
                frontness = -math.sin(angle)
                z_jitter = (
                    0.060 * max(0.0, frontness)
                    - 0.008 * max(0.0, -frontness)
                    - 0.003 * (index % 3)
                )
            vertices.append((
                center.x + math.cos(angle) * ring_radius_x,
                center.y + math.sin(angle) * ring_radius_y,
                z_pos + z_jitter,
            ))

    faces = []
    for index in range(segments):
        faces.append((0, 1 + index, 1 + ((index + 1) % segments)))
    for ring_index in range(len(angles) - 1):
        lower = 1 + ring_index * segments
        upper = 1 + (ring_index + 1) * segments
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((lower + index, upper + index, upper + next_index, lower + next_index))

    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    assign_material(obj, material)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, "Hair")
    return obj


def make_shoe(name, center_x, material, sole_material, parent=None):
    side_sign = 1.0 if center_x > 0.0 else -1.0
    sections = [
        (-0.163, 0.014, 0.073, 0.014, 0.010 * side_sign),
        (-0.145, 0.040, 0.070, 0.038, 0.008 * side_sign),
        (-0.095, 0.052, 0.074, 0.045, 0.004 * side_sign),
        (0.015, 0.049, 0.090, 0.065, 0.001 * side_sign),
        (0.110, 0.042, 0.075, 0.052, 0.000),
        (0.125, 0.023, 0.075, 0.030, -0.001 * side_sign),
    ]
    segments = 14
    vertices = []
    for y_pos, half_width, center_z, half_height, x_offset in sections:
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((
                center_x + x_offset + math.cos(angle) * half_width,
                y_pos,
                center_z + math.sin(angle) * half_height,
            ))
    faces = []
    for section_index in range(len(sections) - 1):
        lower = section_index * segments
        upper = (section_index + 1) * segments
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((lower + index, lower + next_index, upper + next_index, upper + index))
    faces.append(tuple(reversed(range(segments))))
    last = (len(sections) - 1) * segments
    faces.append(tuple(last + index for index in range(segments)))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    for polygon in obj.data.polygons[:-2]:
        polygon.use_smooth = True
    assign_material(obj, material)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, "Leather")

    sole = make_ellipsoid(
        name + "Sole",
        (center_x, -0.020, 0.015),
        (0.057, 0.140, 0.015),
        sole_material,
        parent=parent,
        subdivisions=2,
        category="Leather",
    )
    return obj, sole


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


# Reset the working scene. This MCP-controlled Blender instance was opened for asset generation.
scene = bpy.context.scene
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    bpy.data.collections.remove(collection)
for datablocks in (
    bpy.data.meshes,
    bpy.data.materials,
    bpy.data.cameras,
    bpy.data.lights,
):
    for datablock in list(datablocks):
        if datablock.users == 0:
            datablocks.remove(datablock)

asset_collection = bpy.data.collections.new("CHR_MedievalPeasantRealistic")
preview_collection = bpy.data.collections.new("PREVIEW")
scene.collection.children.link(asset_collection)
scene.collection.children.link(preview_collection)

scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

# Muted, physically plausible dark-fantasy palette.
mat_skin = make_material(
    "MAT_Skin_Weathered", "A9745A", 0.54,
    specular_ior_level=0.36, subsurface_weight=0.045,
)
mat_skin_shadow = make_material(
    "MAT_Skin_Shadow", "765044", 0.60,
    specular_ior_level=0.30, subsurface_weight=0.025,
)
mat_tunic = make_material("MAT_Cloth_Wool_FadedBrown", "594635", 0.88, specular_ior_level=0.27)
mat_tunic_patch = make_material("MAT_Cloth_Wool_Patch", "624B38", 0.91, specular_ior_level=0.25)
mat_linen = make_material("MAT_Cloth_DirtyLinen", "9A8A70", 0.80, specular_ior_level=0.29)
mat_linen_dark = make_material("MAT_Cloth_StainedLinen", "746754", 0.85, specular_ior_level=0.26)
mat_trousers = make_material("MAT_Cloth_Trousers_Taupe", "47443E", 0.87, specular_ior_level=0.27)
mat_leather = make_material("MAT_Leather_Worn", "32251D", 0.64, specular_ior_level=0.34)
mat_sole = make_material("MAT_Leather_Sole", "1C1713", 0.76, specular_ior_level=0.28)
mat_hair = make_material("MAT_Hair_UnkemptBrown", "30251F", 0.77, specular_ior_level=0.30)
mat_eye_white = make_material("MAT_Eye_Sclera", "A99C88", 0.38, specular_ior_level=0.39)
mat_eye_iris = make_material("MAT_Eye_IrisBrown", "3A2A20", 0.30, specular_ior_level=0.40)
mat_eye_pupil = make_material("MAT_Eye_Pupil", "0E0D0C", 0.28, specular_ior_level=0.43)
mat_iron = make_material("MAT_Iron_DullBuckle", "4E4B46", 0.46, metallic=0.55, specular_ior_level=0.36)
mat_ground = make_material("MAT_PREVIEW_Ground", "323232", 0.94, specular_ior_level=0.22)

# Stable runtime hierarchy matching the existing Godot character contract.
root = make_empty("Root", (0.0, 0.0, 0.0))
root["asset_type"] = "character"
root["character_role"] = "medieval_peasant_realistic"
root["height_m"] = 1.765
root["variant"] = "realistic_v2"
root["blender_forward"] = "-Y"
root["godot_forward_after_gltf"] = "-Z"
root["license"] = "Original project asset"

visual_root = make_empty("VisualRoot", (0.0, 0.0, 0.0), root)
pelvis_pivot = make_empty("PelvisPivot", (0.0, 0.0, 0.89), visual_root)
torso_pivot = make_empty("TorsoPivot", (0.0, 0.0, 1.04), pelvis_pivot)
head_pivot = make_empty("HeadPivot", (0.0, 0.0, 1.49), torso_pivot)

# Linen underlayer closes the shoulder and neckline volume beneath the open wool shell.
make_oval_rings(
    "ClothLinenUndershirtTorso",
    [
        (1.180, 0.190, 0.120),
        (1.330, 0.208, 0.132),
        (1.405, 0.196, 0.128),
        (1.438, 0.075, 0.060),
    ],
    24,
    mat_linen,
    parent=torso_pivot,
    smooth=True,
    category="Cloth",
)

# Anatomically scaled tunic: compressed at the belt, fuller over the ribcage,
# and softly flared over the hips instead of a rigid four-sided tube.
tunic = make_oval_rings(
    "ClothTunicWool",
    [
        (0.735, 0.258, 0.142, 0.0, 0.002),
        (0.815, 0.252, 0.141, 0.0, 0.004),
        (0.940, 0.226, 0.132, 0.0, 0.006),
        (0.985, 0.213, 0.126, 0.0, 0.004),
        (1.075, 0.218, 0.132, 0.0, 0.000),
        (1.235, 0.233, 0.145, 0.0, -0.006),
        (1.365, 0.238, 0.151, 0.0, -0.010),
        (1.415, 0.218, 0.145, 0.0, -0.006),
    ],
    24,
    mat_tunic,
    parent=torso_pivot,
    bottom_jitter=(0.000, -0.004, 0.003, -0.006, -0.002, 0.004),
    smooth=True,
    category="Cloth",
    fold_strength=0.028,
    cap_top=False,
)

# Dirty linen collar and a simple split-neck opening.
make_cone_between(
    "ClothLinenCollar",
    (0.0, 0.0, 1.405),
    (0.0, 0.0, 1.445),
    0.074,
    0.060,
    mat_linen,
    parent=torso_pivot,
    vertices=20,
    category="Cloth",
    cap_ends=False,
)
make_triangle_patch(
    "ClothNeckOpening",
    [(-0.038, -0.151, 1.414), (0.038, -0.151, 1.414), (0.0, -0.154, 1.350)],
    mat_linen_dark,
    parent=torso_pivot,
)
make_cone_between(
    "LeatherNeckLaceA",
    (-0.026, -0.156, 1.398),
    (0.019, -0.157, 1.372),
    0.0025,
    0.0025,
    mat_leather,
    parent=torso_pivot,
    vertices=6,
    smooth=False,
    category="Leather",
)
make_cone_between(
    "LeatherNeckLaceB",
    (0.026, -0.156, 1.398),
    (-0.018, -0.157, 1.372),
    0.0025,
    0.0025,
    mat_leather,
    parent=torso_pivot,
    vertices=6,
    smooth=False,
    category="Leather",
)

# Worn repairs and a stitched hem give the garment an ordinary, reused feel.
make_box(
    "ClothTunicPatch",
    (-0.130, -0.137, 0.905),
    (0.090, 0.003, 0.115),
    mat_tunic_patch,
    parent=torso_pivot,
    rotation=(0.0, math.radians(-7.0), 0.0),
    bevel=0.0015,
    category="Cloth",
)
make_box(
    "ClothHemStitch",
    (0.0, -0.145, 0.753),
    (0.420, 0.0015, 0.002),
    mat_tunic_patch,
    parent=torso_pivot,
    bevel=0.001,
    category="Cloth",
)

# Narrow belt, modest iron buckle and one practical pouch.
make_oval_rings(
    "LeatherBelt",
    [(0.966, 0.220, 0.134), (1.000, 0.219, 0.133)],
    24,
    mat_leather,
    parent=pelvis_pivot,
    smooth=False,
    category="Leather",
)
make_box(
    "LeatherBeltBuckle",
    (0.0, -0.143, 0.983),
    (0.050, 0.015, 0.041),
    mat_iron,
    parent=pelvis_pivot,
    bevel=0.004,
    category="Leather",
)
pouch = make_box(
    "LeatherBeltPouch",
    (-0.232, -0.012, 0.905),
    (0.105, 0.060, 0.135),
    mat_leather,
    parent=pelvis_pivot,
    rotation=(0.0, math.radians(-4.0), math.radians(8.0)),
    bevel=0.006,
    category="Leather",
)
make_box(
    "LeatherBeltPouchFlap",
    (-0.232, -0.045, 0.946),
    (0.098, 0.012, 0.052),
    mat_sole,
    parent=pelvis_pivot,
    rotation=(math.radians(-7.0), 0.0, math.radians(8.0)),
    bevel=0.004,
    category="Leather",
)

# Legs and reusable articulation pivots.
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    hip = Vector((0.098 * sign, 0.0, 0.885))
    knee = Vector((0.101 * sign, 0.006, 0.485))
    ankle = Vector((0.102 * sign, 0.0, 0.155))

    leg_pivot = make_empty("Leg{}Pivot".format(side_name), hip, pelvis_pivot)
    knee_pivot = make_empty("Knee{}Pivot".format(side_name), knee, leg_pivot)
    ankle_pivot = make_empty("Ankle{}Pivot".format(side_name), ankle, knee_pivot)

    make_profile_limb(
        "ClothTrouserThigh{}".format(side_name),
        [hip, Vector((0.100 * sign, 0.012, 0.690)), knee],
        [(0.088, 0.077), (0.083, 0.072), (0.063, 0.057)],
        mat_trousers,
        parent=leg_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    make_profile_limb(
        "ClothTrouserShin{}".format(side_name),
        [knee, Vector((0.102 * sign, 0.000, 0.365)), Vector((0.102 * sign, -0.002, 0.245)), ankle],
        [(0.063, 0.057), (0.069, 0.060), (0.057, 0.052), (0.046, 0.043)],
        mat_trousers,
        parent=knee_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )

    # A single muted puttee volume with shallow overlapping wraps.
    make_profile_limb(
        "ClothLegWrap{}".format(side_name),
        [
            Vector((0.102 * sign, -0.001, 0.180)),
            Vector((0.102 * sign, -0.001, 0.285)),
            Vector((0.102 * sign, 0.000, 0.405)),
        ],
        [(0.052, 0.048), (0.061, 0.054), (0.063, 0.056)],
        mat_linen_dark,
        parent=knee_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    for wrap_index, center_z in enumerate((0.215, 0.270, 0.325, 0.380)):
        center_x = knee.x + (ankle.x - knee.x) * ((knee.z - center_z) / (knee.z - ankle.z))
        make_cone_between(
            "ClothCalfWrap{}{}".format(side_name, wrap_index + 1),
            (center_x, 0.0, center_z - 0.007),
            (center_x, 0.0, center_z + 0.007),
            0.056 + 0.0025 * wrap_index,
            0.057 + 0.0025 * wrap_index,
            mat_linen_dark,
            parent=knee_pivot,
            vertices=18,
            category="Cloth",
            cap_ends=False,
        )

    make_cone_between(
        "LeatherAnkleTie{}".format(side_name),
        (ankle.x, 0.0, 0.155),
        (ankle.x, 0.0, 0.185),
        0.054,
        0.055,
        mat_leather,
        parent=ankle_pivot,
        vertices=18,
        category="Leather",
        cap_ends=False,
    )
    make_shoe("LeatherShoe{}".format(side_name), ankle.x, mat_leather, mat_sole, parent=ankle_pivot)

# Arms in a neutral A-pose, with short wool sleeves over long linen sleeves.
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    shoulder = Vector((0.205 * sign, 0.0, 1.405))
    sleeve_end = Vector((0.292 * sign, -0.003, 1.322))
    elbow = Vector((0.390 * sign, -0.012, 1.190))
    wrist = Vector((0.485 * sign, -0.018, 1.005))
    hand_center = Vector((0.518 * sign, -0.024, 0.915))

    shoulder_pivot = make_empty("Shoulder{}Pivot".format(side_name), shoulder, torso_pivot)
    arm_pivot = make_empty("Arm{}Pivot".format(side_name), shoulder, shoulder_pivot)
    elbow_pivot = make_empty("Elbow{}Pivot".format(side_name), elbow, arm_pivot)
    wrist_pivot = make_empty("Wrist{}Pivot".format(side_name), wrist, elbow_pivot)
    hand_parent = wrist_pivot
    if side_name == "R":
        hand_parent = make_empty("WeaponPivot", wrist, wrist_pivot)
    hand_pivot = make_empty("Hand{}Pivot".format(side_name), hand_center, hand_parent)

    make_profile_limb(
        "ClothTunicSleeve{}".format(side_name),
        [shoulder, Vector((0.247 * sign, -0.002, 1.372)), sleeve_end],
        [(0.047, 0.051), (0.060, 0.062), (0.055, 0.057)],
        mat_tunic,
        parent=arm_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    make_profile_limb(
        "ClothLinenUpperSleeve{}".format(side_name),
        [sleeve_end, Vector((0.342 * sign, -0.008, 1.258)), elbow],
        [(0.057, 0.059), (0.054, 0.056), (0.046, 0.049)],
        mat_linen,
        parent=arm_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    make_profile_limb(
        "ClothLinenForearm{}".format(side_name),
        [elbow, Vector((0.438 * sign, -0.017, 1.105)), wrist],
        [(0.046, 0.049), (0.043, 0.045), (0.035, 0.038)],
        mat_linen,
        parent=elbow_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    make_cone_between(
        "ClothLinenCuff{}".format(side_name),
        wrist - (wrist - elbow).normalized() * 0.012,
        wrist + (wrist - elbow).normalized() * 0.020,
        0.039,
        0.039,
        mat_linen_dark,
        parent=wrist_pivot,
        vertices=18,
        category="Cloth",
        cap_ends=False,
    )
    hand_direction = (hand_center - wrist).normalized()
    make_ellipsoid_aligned(
        "BodyHand{}".format(side_name),
        hand_center,
        (0.035, 0.024, 0.058),
        hand_direction,
        mat_skin,
        parent=hand_pivot,
        category="Body",
    )
    finger_base = hand_center + hand_direction * 0.046
    finger_lengths = (0.071, 0.078, 0.075, 0.064)
    for finger_index, (y_offset, finger_length) in enumerate(zip((-0.023, -0.008, 0.008, 0.022), finger_lengths)):
        finger_center = finger_base + Vector((0.0, y_offset, 0.0)) + hand_direction * (finger_length * 0.5)
        make_ellipsoid_aligned(
            "BodyFinger{}{}".format(side_name, finger_index + 1),
            finger_center,
            (0.0075, 0.0065, finger_length * 0.5),
            hand_direction,
            mat_skin,
            parent=hand_pivot,
            category="Body",
        )
    thumb_start = hand_center + Vector((-0.012 * sign, -0.022, 0.008))
    thumb_end = thumb_start + Vector((-0.028 * sign, -0.015, -0.035))
    make_cone_between(
        "BodyThumb{}".format(side_name),
        thumb_start,
        thumb_end,
        0.011,
        0.008,
        mat_skin,
        parent=hand_pivot,
        vertices=10,
        category="Body",
    )

# Neck and a proportionally realistic, weathered non-heroic face.
make_cone_between(
    "BodyNeck",
    (0.0, 0.0, 1.410),
    (0.0, 0.0, 1.515),
    0.059,
    0.055,
    mat_skin,
    parent=head_pivot,
    vertices=20,
    category="Body",
    cap_ends=False,
)
head = make_oval_rings(
    "BodyHead",
    [
        (1.510, 0.042, 0.055, 0.0, -0.010),
        (1.535, 0.068, 0.069, 0.0, -0.004),
        (1.585, 0.077, 0.083, 0.0, 0.000),
        (1.640, 0.080, 0.092, 0.0, 0.004),
        (1.700, 0.076, 0.090, 0.0, 0.006),
        (1.748, 0.050, 0.060, 0.0, 0.006),
    ],
    24,
    mat_skin,
    parent=head_pivot,
    smooth=True,
    category="Body",
)
make_ellipsoid("BodyEarL", (0.081, 0.003, 1.625), (0.016, 0.010, 0.030), mat_skin_shadow, head_pivot, 2, "Body")
make_ellipsoid("BodyEarR", (-0.081, 0.002, 1.624), (0.016, 0.010, 0.030), mat_skin_shadow, head_pivot, 2, "Body")

# Small sclera, irises and pupils avoid the black-button-eye look.
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    make_ellipsoid(
        "EyeSclera{}".format(side_name),
        (0.029 * sign, -0.086, 1.635 + 0.001 * sign),
        (0.014, 0.0055, 0.0070),
        mat_eye_white,
        head_pivot,
        2,
        "Eye",
    )
    make_ellipsoid(
        "EyeIris{}".format(side_name),
        (0.029 * sign, -0.0915, 1.635 + 0.001 * sign),
        (0.0055, 0.0028, 0.0055),
        mat_eye_iris,
        head_pivot,
        2,
        "Eye",
    )
    make_ellipsoid(
        "EyePupil{}".format(side_name),
        (0.029 * sign, -0.0940, 1.635 + 0.001 * sign),
        (0.0027, 0.0018, 0.0027),
        mat_eye_pupil,
        head_pivot,
        1,
        "Eye",
    )
    make_cone_between(
        "HairBrow{}".format(side_name),
        (0.012 * sign, -0.090, 1.656 + 0.001 * sign),
        (0.052 * sign, -0.087, 1.659 - 0.002 * sign),
        0.0045,
        0.0030,
        mat_hair,
        parent=head_pivot,
        vertices=8,
        smooth=True,
        category="Hair",
    )

make_ellipsoid_aligned(
    "BodyNoseBridge",
    (0.0, -0.091, 1.626),
    (0.014, 0.012, 0.034),
    (0.0, -0.55, -0.84),
    mat_skin,
    parent=head_pivot,
    category="Body",
)
make_ellipsoid(
    "BodyNoseTip",
    (0.0, -0.111, 1.598),
    (0.018, 0.013, 0.014),
    mat_skin,
    head_pivot,
    2,
    "Body",
)
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    make_ellipsoid(
        "BodyNostril{}".format(side_name),
        (0.008 * sign, -0.121, 1.594),
        (0.0040, 0.0022, 0.0028),
        mat_skin_shadow,
        head_pivot,
        1,
        "Body",
    )

make_ellipsoid(
    "BodyUpperLip",
    (0.0, -0.081, 1.566),
    (0.025, 0.005, 0.0035),
    mat_skin_shadow,
    head_pivot,
    2,
    "Body",
)
make_ellipsoid(
    "BodyLowerLip",
    (0.0, -0.080, 1.558),
    (0.022, 0.005, 0.0040),
    mat_skin,
    head_pivot,
    2,
    "Body",
)

# Short facial hair following the jaw instead of a single beard sphere.
make_ellipsoid(
    "HairChinBeard",
    (0.0, -0.052, 1.525),
    (0.037, 0.018, 0.030),
    mat_hair,
    head_pivot,
    2,
    "Hair",
)
make_ellipsoid("HairJawL", (0.041, -0.057, 1.547), (0.025, 0.013, 0.027), mat_hair, head_pivot, 2, "Hair")
make_ellipsoid("HairJawR", (-0.041, -0.057, 1.547), (0.025, 0.013, 0.027), mat_hair, head_pivot, 2, "Hair")
make_ellipsoid("HairMoustacheL", (0.019, -0.086, 1.575), (0.023, 0.007, 0.006), mat_hair, head_pivot, 2, "Hair")
make_ellipsoid("HairMoustacheR", (-0.019, -0.086, 1.575), (0.023, 0.007, 0.006), mat_hair, head_pivot, 2, "Hair")
make_ellipsoid(
    "HairCrown",
    (0.0, 0.010, 1.690),
    (0.090, 0.103, 0.075),
    mat_hair,
    head_pivot,
    3,
    "Hair",
)
make_hair_cap(
    "HairUnkemptCap", (0.0, 0.008, 1.630), mat_hair, head_pivot,
    radius_x=0.095, radius_y=0.108, height=0.135,
)
for index, (root_point, tip_point) in enumerate((
    ((-0.052, -0.078, 1.723), (-0.058, -0.092, 1.676)),
    ((-0.008, -0.086, 1.739), (-0.012, -0.101, 1.686)),
    ((0.039, -0.080, 1.725), (0.047, -0.094, 1.680)),
)):
    make_cone_between(
        "HairForelock{}".format(index + 1),
        root_point,
        tip_point,
        0.011,
        0.0015,
        mat_hair,
        parent=head_pivot,
        vertices=8,
        smooth=False,
        category="Hair",
    )

# Preview-only neutral studio floor, camera and soft three-point lighting.
bpy.ops.mesh.primitive_plane_add(size=5.0, location=(0.0, 0.0, 0.0))
platform = bpy.context.object
platform.name = "PREVIEW_Floor"
assign_material(platform, mat_ground)
move_to_collection(platform, preview_collection)

camera_data = bpy.data.cameras.new("PREVIEW_CameraData")
camera_data.lens = 70.0
camera = bpy.data.objects.new("PREVIEW_Camera", camera_data)
preview_collection.objects.link(camera)
scene.camera = camera


def add_area_light(name, location, energy, color, size):
    light_data = bpy.data.lights.new(name + "Data", type="AREA")
    light_data.energy = energy
    light_data.color = color
    light_data.shape = "DISK"
    light_data.size = size
    light = bpy.data.objects.new(name, light_data)
    light.location = location
    preview_collection.objects.link(light)
    look_at(light, (0.0, 0.0, 0.95))
    return light


add_area_light("PREVIEW_Key", (-3.0, -4.0, 4.5), 880.0, (1.0, 0.91, 0.82), 3.4)
add_area_light("PREVIEW_Fill", (3.1, -1.2, 2.8), 420.0, (0.72, 0.80, 0.92), 3.2)
add_area_light("PREVIEW_Rim", (0.8, 3.4, 3.5), 560.0, (1.0, 0.86, 0.72), 2.6)

world = scene.world or bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
background = world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = color_from_hex("17191B")
background.inputs["Strength"].default_value = 0.32

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
try:
    scene.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    pass

# Save the authoring file with preview setup intact.
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

# Export only the character hierarchy, not cameras/lights/platform.
bpy.ops.object.select_all(action="DESELECT")
for obj in asset_collection.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root

gltf_properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
gltf_args = {
    "filepath": GLB_PATH,
    "export_format": "GLB",
}
optional_gltf_args = {
    "use_selection": True,
    "export_yup": True,
    "export_apply": True,
    "export_cameras": False,
    "export_lights": False,
    "export_extras": True,
}
for key, value in optional_gltf_args.items():
    if key in gltf_properties:
        gltf_args[key] = value
bpy.ops.export_scene.gltf(**gltf_args)

# Render a compact turntable set for visual QA.
views = {
    "three_quarter": ((2.85, -4.15, 1.72), (0.0, 0.0, 0.90)),
    "front": ((0.0, -4.60, 1.18), (0.0, 0.0, 0.89)),
    "side": ((4.60, 0.0, 1.18), (0.0, 0.0, 0.89)),
    "back": ((0.0, 4.60, 1.18), (0.0, 0.0, 0.89)),
}
preview_paths = []
for view_name, (camera_location, target) in views.items():
    camera.location = camera_location
    look_at(camera, target)
    output_path = os.path.join(PREVIEW_DIR, "medieval_peasant_realistic_{}.png".format(view_name))
    scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
    preview_paths.append(output_path)

# Restore the authored three-quarter view and save again.
camera.location = views["three_quarter"][0]
look_at(camera, views["three_quarter"][1])
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

mesh_objects = [obj for obj in asset_collection.objects if obj.type == "MESH"]
triangle_count = 0
for obj in mesh_objects:
    for polygon in obj.data.polygons:
        triangle_count += max(1, len(polygon.vertices) - 2)

result = {
    "status": "ok",
    "asset": "medieval_peasant_realistic_3d",
    "height_m": 1.765,
    "mesh_objects": len(mesh_objects),
    "triangle_count_authored": triangle_count,
    "blend_path": BLEND_PATH,
    "glb_path": GLB_PATH,
    "preview_paths": preview_paths,
    "root": root.name,
    "forward_blender": "-Y",
    "forward_godot": "-Z",
}
