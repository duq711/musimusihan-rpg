import bpy
import math
import os
from mathutils import Vector


STAGING_DIR = "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_medieval_peasant"
PREVIEW_DIR = os.path.join(STAGING_DIR, "previews")
BLEND_PATH = os.path.join(STAGING_DIR, "medieval_peasant_3d.blend")
GLB_PATH = "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/3d/dark_fantasy/medieval_peasant_3d.glb"

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


def make_material(name, hex_color, roughness, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    rgba = color_from_hex(hex_color)
    material.diffuse_color = rgba
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
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
                      vertices=10, smooth=True, category="Body"):
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
        end_fill_type="NGON",
        location=midpoint,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    assign_material(obj, material)
    move_to_collection(obj, asset_collection)
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


def make_oval_rings(name, rings, segments, material, parent=None, bottom_jitter=None,
                    smooth=False, category="Cloth"):
    vertices = []
    for ring_index, (z_pos, radius_x, radius_y) in enumerate(rings):
        for index in range(segments):
            angle = (math.tau * index / segments) + (math.pi / segments)
            jitter = 0.0
            if ring_index == 0 and bottom_jitter:
                jitter = bottom_jitter[index % len(bottom_jitter)]
            vertices.append((
                math.cos(angle) * radius_x,
                math.sin(angle) * radius_y,
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
    faces.append(tuple(reversed(range(segments))))
    top_start = (len(rings) - 1) * segments
    faces.append(tuple(top_start + index for index in range(segments)))

    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    if smooth:
        for polygon in obj.data.polygons:
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


def make_hair_cap(name, center, material, parent=None):
    center = Vector(center)
    segments = 12
    angles = [18.0, 40.0, 62.0, 82.0, 103.0]
    vertices = [(center.x, center.y, center.z + 0.174)]
    for ring_index, angle_degrees in enumerate(angles):
        polar = math.radians(angle_degrees)
        radius_x = math.sin(polar) * 0.138
        radius_y = math.sin(polar) * 0.123
        z_pos = center.z + math.cos(polar) * 0.174
        for index in range(segments):
            angle = math.tau * index / segments
            z_jitter = 0.0
            if ring_index == len(angles) - 1:
                # Uneven cropped hairline, slightly longer at the rear and temples.
                frontness = -math.sin(angle)
                z_jitter = -0.010 * (index % 3) - 0.020 * max(0.0, -frontness)
            vertices.append((
                center.x + math.cos(angle) * radius_x,
                center.y + math.sin(angle) * radius_y,
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
    assign_material(obj, material)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, "Hair")
    return obj


def make_shoe(name, center_x, material, sole_material, parent=None):
    x_left = center_x - 0.105
    x_right = center_x + 0.105
    vertices = [
        (x_left, -0.225, 0.027),
        (x_right, -0.225, 0.027),
        (center_x + 0.095, 0.085, 0.027),
        (center_x - 0.095, 0.085, 0.027),
        (center_x - 0.092, -0.205, 0.112),
        (center_x + 0.092, -0.205, 0.112),
        (center_x + 0.078, 0.068, 0.170),
        (center_x - 0.078, 0.068, 0.170),
    ]
    faces = [
        (0, 1, 2, 3),
        (4, 7, 6, 5),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    ]
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, "Leather")

    sole = make_box(
        name + "Sole",
        (center_x, -0.068, 0.013),
        (0.215, 0.318, 0.026),
        sole_material,
        parent=parent,
        bevel=0.006,
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

asset_collection = bpy.data.collections.new("CHR_MedievalPeasant")
preview_collection = bpy.data.collections.new("PREVIEW")
scene.collection.children.link(asset_collection)
scene.collection.children.link(preview_collection)

scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

# Restrained, dirty dark-fantasy palette.
mat_skin = make_material("MAT_Skin_SunWorn", "B97855", 0.78)
mat_skin_shadow = make_material("MAT_Skin_Shadow", "7E4938", 0.82)
mat_tunic = make_material("MAT_Cloth_Wool_FadedBrown", "6B4E32", 0.92)
mat_tunic_patch = make_material("MAT_Cloth_Wool_Patch", "806044", 0.94)
mat_linen = make_material("MAT_Cloth_DirtyLinen", "B8A27D", 0.86)
mat_linen_dark = make_material("MAT_Cloth_StainedLinen", "867359", 0.90)
mat_trousers = make_material("MAT_Cloth_Trousers_Taupe", "514A40", 0.91)
mat_leather = make_material("MAT_Leather_Worn", "3A291C", 0.70)
mat_sole = make_material("MAT_Leather_Sole", "201711", 0.82)
mat_hair = make_material("MAT_Hair_UnkemptBrown", "2C2018", 0.88)
mat_eye = make_material("MAT_Eye_Dark", "171310", 0.55)
mat_iron = make_material("MAT_Iron_DullBuckle", "5B5750", 0.58, metallic=0.35)
mat_ground = make_material("MAT_PREVIEW_Ground", "26282A", 0.93)

# Stable runtime hierarchy matching the existing Godot character contract.
root = make_empty("Root", (0.0, 0.0, 0.0))
root["asset_type"] = "character"
root["character_role"] = "medieval_peasant"
root["height_m"] = 1.765
root["blender_forward"] = "-Y"
root["godot_forward_after_gltf"] = "-Z"
root["license"] = "Original project asset"

visual_root = make_empty("VisualRoot", (0.0, 0.0, 0.0), root)
pelvis_pivot = make_empty("PelvisPivot", (0.0, 0.0, 0.89), visual_root)
torso_pivot = make_empty("TorsoPivot", (0.0, 0.0, 1.04), pelvis_pivot)
head_pivot = make_empty("HeadPivot", (0.0, 0.0, 1.45), torso_pivot)

# Tunic body with an uneven, work-worn hem.
tunic = make_oval_rings(
    "ClothTunicWool",
    [
        (0.775, 0.295, 0.150),
        (0.965, 0.255, 0.142),
        (1.180, 0.242, 0.137),
        (1.355, 0.298, 0.145),
    ],
    12,
    mat_tunic,
    parent=torso_pivot,
    bottom_jitter=(0.000, -0.012, 0.008, -0.019, -0.006, 0.010),
    smooth=False,
    category="Cloth",
)

# Dirty linen collar and a simple split-neck opening.
make_cone_between(
    "ClothLinenCollar",
    (0.0, 0.0, 1.345),
    (0.0, 0.0, 1.435),
    0.115,
    0.083,
    mat_linen,
    parent=torso_pivot,
    vertices=12,
    category="Cloth",
)
make_triangle_patch(
    "ClothNeckOpening",
    [(-0.052, -0.151, 1.350), (0.052, -0.151, 1.350), (0.0, -0.158, 1.260)],
    mat_linen_dark,
    parent=torso_pivot,
)
make_cone_between(
    "LeatherNeckLaceA",
    (-0.038, -0.161, 1.325),
    (0.033, -0.161, 1.295),
    0.005,
    0.005,
    mat_leather,
    parent=torso_pivot,
    vertices=6,
    smooth=False,
    category="Leather",
)
make_cone_between(
    "LeatherNeckLaceB",
    (0.038, -0.162, 1.325),
    (-0.030, -0.162, 1.292),
    0.005,
    0.005,
    mat_leather,
    parent=torso_pivot,
    vertices=6,
    smooth=False,
    category="Leather",
)

# Worn repairs and a stitched hem give the garment an ordinary, reused feel.
make_box(
    "ClothTunicPatch",
    (-0.132, -0.151, 0.995),
    (0.135, 0.012, 0.165),
    mat_tunic_patch,
    parent=torso_pivot,
    rotation=(0.0, math.radians(-7.0), 0.0),
    bevel=0.006,
    category="Cloth",
)
make_box(
    "ClothHemStitch",
    (0.0, -0.157, 0.807),
    (0.47, 0.010, 0.014),
    mat_linen_dark,
    parent=torso_pivot,
    bevel=0.003,
    category="Cloth",
)

# Narrow belt, modest iron buckle and one practical pouch.
make_oval_rings(
    "LeatherBelt",
    [(0.955, 0.266, 0.153), (1.015, 0.263, 0.151)],
    14,
    mat_leather,
    parent=pelvis_pivot,
    smooth=False,
    category="Leather",
)
make_box(
    "LeatherBeltBuckle",
    (0.0, -0.166, 0.985),
    (0.072, 0.026, 0.078),
    mat_iron,
    parent=pelvis_pivot,
    bevel=0.008,
    category="Leather",
)
pouch = make_box(
    "LeatherBeltPouch",
    (-0.270, -0.018, 0.905),
    (0.145, 0.085, 0.180),
    mat_leather,
    parent=pelvis_pivot,
    rotation=(0.0, math.radians(-4.0), math.radians(8.0)),
    bevel=0.018,
    category="Leather",
)
make_box(
    "LeatherBeltPouchFlap",
    (-0.270, -0.066, 0.957),
    (0.135, 0.020, 0.073),
    mat_sole,
    parent=pelvis_pivot,
    rotation=(math.radians(-7.0), 0.0, math.radians(8.0)),
    bevel=0.012,
    category="Leather",
)

# Legs and reusable articulation pivots.
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    hip = Vector((0.115 * sign, 0.0, 0.885))
    knee = Vector((0.132 * sign, 0.002, 0.485))
    ankle = Vector((0.142 * sign, 0.0, 0.165))

    leg_pivot = make_empty("Leg{}Pivot".format(side_name), hip, pelvis_pivot)
    knee_pivot = make_empty("Knee{}Pivot".format(side_name), knee, leg_pivot)
    ankle_pivot = make_empty("Ankle{}Pivot".format(side_name), ankle, knee_pivot)

    make_cone_between(
        "ClothTrouserThigh{}".format(side_name),
        hip,
        knee,
        0.108,
        0.082,
        mat_trousers,
        parent=leg_pivot,
        vertices=10,
        category="Cloth",
    )
    make_cone_between(
        "ClothTrouserShin{}".format(side_name),
        knee,
        ankle,
        0.080,
        0.061,
        mat_trousers,
        parent=knee_pivot,
        vertices=10,
        category="Cloth",
    )

    # Three visible wraps around each calf.
    for wrap_index, center_z in enumerate((0.245, 0.315, 0.385)):
        center_x = knee.x + (ankle.x - knee.x) * ((knee.z - center_z) / (knee.z - ankle.z))
        make_cone_between(
            "ClothCalfWrap{}{}".format(side_name, wrap_index + 1),
            (center_x, 0.0, center_z - 0.022),
            (center_x, 0.0, center_z + 0.022),
            0.075,
            0.076,
            mat_linen_dark if wrap_index == 1 else mat_linen,
            parent=knee_pivot,
            vertices=10,
            category="Cloth",
        )

    make_cone_between(
        "LeatherBootShaft{}".format(side_name),
        (ankle.x, 0.0, 0.115),
        (ankle.x, 0.0, 0.275),
        0.074,
        0.083,
        mat_leather,
        parent=ankle_pivot,
        vertices=10,
        category="Leather",
    )
    make_shoe("LeatherShoe{}".format(side_name), ankle.x, mat_leather, mat_sole, parent=ankle_pivot)

# Arms in a neutral A-pose, with short wool sleeves over long linen sleeves.
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    shoulder = Vector((0.282 * sign, 0.0, 1.350))
    sleeve_end = Vector((0.430 * sign, 0.0, 1.255))
    elbow = Vector((0.545 * sign, -0.002, 1.165))
    wrist = Vector((0.700 * sign, -0.008, 1.045))
    hand_center = Vector((0.742 * sign, -0.014, 0.988))

    shoulder_pivot = make_empty("Shoulder{}Pivot".format(side_name), shoulder, torso_pivot)
    arm_pivot = make_empty("Arm{}Pivot".format(side_name), shoulder, shoulder_pivot)
    elbow_pivot = make_empty("Elbow{}Pivot".format(side_name), elbow, arm_pivot)
    wrist_pivot = make_empty("Wrist{}Pivot".format(side_name), wrist, elbow_pivot)
    hand_pivot = make_empty("Hand{}Pivot".format(side_name), hand_center, wrist_pivot)

    make_cone_between(
        "ClothTunicSleeve{}".format(side_name),
        shoulder,
        sleeve_end,
        0.132,
        0.108,
        mat_tunic,
        parent=arm_pivot,
        vertices=10,
        category="Cloth",
    )
    make_cone_between(
        "ClothLinenUpperSleeve{}".format(side_name),
        sleeve_end,
        elbow,
        0.097,
        0.082,
        mat_linen,
        parent=arm_pivot,
        vertices=10,
        category="Cloth",
    )
    make_cone_between(
        "ClothLinenForearm{}".format(side_name),
        elbow,
        wrist,
        0.081,
        0.058,
        mat_linen,
        parent=elbow_pivot,
        vertices=10,
        category="Cloth",
    )
    make_cone_between(
        "ClothLinenCuff{}".format(side_name),
        wrist - (wrist - elbow).normalized() * 0.022,
        wrist + (wrist - elbow).normalized() * 0.028,
        0.064,
        0.064,
        mat_linen_dark,
        parent=wrist_pivot,
        vertices=10,
        category="Cloth",
    )
    hand_direction = (hand_center - wrist).normalized()
    hand = make_ellipsoid_aligned(
        "BodyHand{}".format(side_name),
        hand_center,
        (0.052, 0.043, 0.073),
        hand_direction,
        mat_skin,
        parent=hand_pivot,
        category="Body",
    )
    make_cone_between(
        "BodyThumb{}".format(side_name),
        hand_center + Vector((-0.015 * sign, -0.018, 0.010)),
        hand_center + Vector((-0.040 * sign, -0.030, -0.025)),
        0.020,
        0.014,
        mat_skin,
        parent=hand_pivot,
        vertices=7,
        category="Body",
    )

# Neck and weathered, non-heroic face.
make_cone_between(
    "BodyNeck",
    (0.0, 0.0, 1.395),
    (0.0, 0.0, 1.490),
    0.090,
    0.082,
    mat_skin,
    parent=head_pivot,
    vertices=10,
    category="Body",
)
head = make_ellipsoid(
    "BodyHead",
    (0.0, 0.0, 1.585),
    (0.132, 0.114, 0.158),
    mat_skin,
    parent=head_pivot,
    subdivisions=2,
    category="Body",
)
make_ellipsoid("BodyEarL", (0.132, 0.0, 1.592), (0.027, 0.020, 0.041), mat_skin_shadow, head_pivot, 1, "Body")
make_ellipsoid("BodyEarR", (-0.132, 0.0, 1.592), (0.027, 0.020, 0.041), mat_skin_shadow, head_pivot, 1, "Body")

# Eyes, tired brows, broad working nose and subtle mouth.
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    make_ellipsoid(
        "Eye{}".format(side_name),
        (0.046 * sign, -0.108, 1.626),
        (0.017, 0.010, 0.012),
        mat_eye,
        head_pivot,
        1,
        "Eye",
    )
    make_box(
        "HairBrow{}".format(side_name),
        (0.047 * sign, -0.114, 1.657 - 0.004 * sign),
        (0.058, 0.010, 0.011),
        mat_hair,
        parent=head_pivot,
        rotation=(0.0, math.radians(-7.0 * sign), 0.0),
        bevel=0.003,
        category="Hair",
    )

make_cone_between(
    "BodyNose",
    (0.0, -0.098, 1.600),
    (0.0, -0.181, 1.568),
    0.036,
    0.014,
    mat_skin,
    parent=head_pivot,
    vertices=7,
    smooth=False,
    category="Body",
)
make_box(
    "BodyMouth",
    (0.0, -0.116, 1.522),
    (0.067, 0.010, 0.009),
    mat_skin_shadow,
    parent=head_pivot,
    bevel=0.003,
    category="Body",
)

# Short, untidy beard and hair cap.
make_ellipsoid(
    "HairShortBeard",
    (0.0, -0.063, 1.485),
    (0.100, 0.068, 0.073),
    mat_hair,
    head_pivot,
    2,
    "Hair",
)
make_ellipsoid("HairMoustacheL", (0.030, -0.123, 1.540), (0.039, 0.014, 0.013), mat_hair, head_pivot, 1, "Hair")
make_ellipsoid("HairMoustacheR", (-0.030, -0.123, 1.540), (0.039, 0.014, 0.013), mat_hair, head_pivot, 1, "Hair")
make_hair_cap("HairUnkemptCap", (0.0, 0.006, 1.590), mat_hair, head_pivot)
for index, (root_point, tip_point) in enumerate((
    ((-0.072, -0.103, 1.710), (-0.082, -0.132, 1.651)),
    ((-0.012, -0.115, 1.724), (-0.022, -0.139, 1.662)),
    ((0.052, -0.108, 1.711), (0.064, -0.134, 1.655)),
)):
    make_cone_between(
        "HairForelock{}".format(index + 1),
        root_point,
        tip_point,
        0.027,
        0.002,
        mat_hair,
        parent=head_pivot,
        vertices=6,
        smooth=False,
        category="Hair",
    )

# Preview-only platform, camera and three-point lighting.
bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1.05, depth=0.07, location=(0.0, 0.0, -0.035))
platform = bpy.context.object
platform.name = "PREVIEW_Platform"
assign_material(platform, mat_ground)
move_to_collection(platform, preview_collection)

camera_data = bpy.data.cameras.new("PREVIEW_CameraData")
camera_data.lens = 58.0
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


add_area_light("PREVIEW_Key", (-3.0, -4.0, 4.5), 760.0, (1.0, 0.72, 0.48), 3.2)
add_area_light("PREVIEW_Fill", (3.1, -1.2, 2.8), 430.0, (0.47, 0.62, 0.85), 3.0)
add_area_light("PREVIEW_Rim", (0.8, 3.4, 3.5), 680.0, (1.0, 0.48, 0.27), 2.4)

world = scene.world or bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
background = world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = color_from_hex("11161A")
background.inputs["Strength"].default_value = 0.28

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 720
scene.render.resolution_y = 720
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
    "three_quarter": ((2.45, -3.55, 1.72), (0.0, 0.0, 0.91)),
    "front": ((0.0, -3.80, 1.18), (0.0, 0.0, 0.90)),
    "side": ((3.80, 0.0, 1.18), (0.0, 0.0, 0.90)),
    "back": ((0.0, 3.80, 1.18), (0.0, 0.0, 0.90)),
}
preview_paths = []
for view_name, (camera_location, target) in views.items():
    camera.location = camera_location
    look_at(camera, target)
    output_path = os.path.join(PREVIEW_DIR, "medieval_peasant_{}.png".format(view_name))
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
    "asset": "medieval_peasant_3d",
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
