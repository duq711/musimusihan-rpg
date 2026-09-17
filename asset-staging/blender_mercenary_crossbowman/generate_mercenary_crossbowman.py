import bpy
import math
import os
from mathutils import Vector


STAGING_DIR = "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_mercenary_crossbowman"
PREVIEW_DIR = os.path.join(STAGING_DIR, "previews")
BLEND_PATH = os.path.join(STAGING_DIR, "mercenary_crossbowman_3d.blend")
GLB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(STAGING_DIR)),
    "godot-game", "assets", "3d", "dark_fantasy", "mercenary_crossbowman_3d.glb",
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


def add_surface_noise(
    material,
    scale,
    bump_strength,
    bump_distance,
    dark_hex=None,
    light_hex=None,
    detail=4.0,
):
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    texcoord = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = detail
    noise.inputs["Roughness"].default_value = 0.72
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = bump_distance
    links.new(texcoord.outputs["Generated"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    if dark_hex and light_hex:
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.23
        ramp.color_ramp.elements[0].color = color_from_hex(dark_hex)
        ramp.color_ramp.elements[1].position = 0.78
        ramp.color_ramp.elements[1].color = color_from_hex(light_hex)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])


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


def make_box_between(
    name,
    point_a,
    point_b,
    width,
    thickness,
    material,
    parent=None,
    bevel=0.0,
    category="Leather",
):
    point_a = Vector(point_a)
    point_b = Vector(point_b)
    direction = point_b - point_a
    obj = make_box(
        name,
        (point_a + point_b) * 0.5,
        (width, thickness, direction.length),
        material,
        parent=None,
        bevel=bevel,
        category=category,
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    if parent is not None:
        parent_keep_world(obj, parent)
    return obj


def make_elliptical_torus(
    name,
    location,
    major_radius,
    minor_radius,
    material,
    parent=None,
    scale=(1.0, 1.0, 1.0),
    rotation=(0.0, 0.0, 0.0),
    category="Cloth",
    major_segments=32,
    minor_segments=8,
):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=major_segments,
        minor_segments=minor_segments,
        major_radius=major_radius,
        minor_radius=minor_radius,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    assign_material(obj, material)
    move_to_collection(obj, asset_collection)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag_part(obj, category)
    return obj


def make_extruded_panel(
    name,
    outline,
    center,
    axis_u,
    axis_v,
    thickness,
    material,
    parent=None,
    category="Cloth",
):
    outline = list(outline)
    signed_area = 0.0
    for index, (u_pos, v_pos) in enumerate(outline):
        next_u, next_v = outline[(index + 1) % len(outline)]
        signed_area += (u_pos * next_v) - (next_u * v_pos)
    if signed_area < 0.0:
        outline.reverse()
    center = Vector(center)
    axis_u = Vector(axis_u).normalized()
    axis_v = Vector(axis_v).normalized()
    normal = axis_u.cross(axis_v).normalized()
    half = thickness * 0.5
    vertices = []
    for normal_offset in (half, -half):
        for u_pos, v_pos in outline:
            vertices.append(center + axis_u * u_pos + axis_v * v_pos + normal * normal_offset)
    count = len(outline)
    faces = [tuple(range(count)), tuple(reversed(range(count, count * 2)))]
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    bevel_modifier = obj.modifiers.new("SoftClothEdges", "BEVEL")
    bevel_modifier.width = min(0.0035, thickness * 0.22)
    bevel_modifier.segments = 2
    bevel_modifier.limit_method = "ANGLE"
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel_modifier.name)
    if parent is not None:
        parent_keep_world(obj, parent)
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
        (-0.175, 0.016, 0.073, 0.014, 0.010 * side_sign),
        (-0.155, 0.045, 0.070, 0.040, 0.008 * side_sign),
        (-0.100, 0.058, 0.074, 0.047, 0.004 * side_sign),
        (0.015, 0.055, 0.090, 0.067, 0.001 * side_sign),
        (0.115, 0.047, 0.075, 0.054, 0.000),
        (0.132, 0.026, 0.075, 0.032, -0.001 * side_sign),
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
        (0.062, 0.150, 0.016),
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

asset_collection = bpy.data.collections.new("CHR_MercenaryCrossbowman")
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
mat_tunic = make_material("MAT_Cloth_OuterCoatCharcoal", "2D2B28", 0.91, specular_ior_level=0.24)
mat_tunic_patch = make_material("MAT_Cloth_OuterCoatWorn", "3A3631", 0.93, specular_ior_level=0.23)
mat_linen = make_material("MAT_Cloth_QuiltedGambeson", "716A60", 0.86, specular_ior_level=0.27)
mat_linen_dark = make_material("MAT_Cloth_GambesonStitch", "504B43", 0.90, specular_ior_level=0.24)
mat_trousers = make_material("MAT_Cloth_TrousersCharcoal", "302F2D", 0.91, specular_ior_level=0.24)
mat_leather = make_material("MAT_Leather_DarkWorn", "30251D", 0.66, specular_ior_level=0.34)
mat_leather_light = make_material("MAT_Leather_Straps", "4A3829", 0.63, specular_ior_level=0.35)
mat_leather_edge = make_material("MAT_Leather_EdgeWear", "66503A", 0.58, specular_ior_level=0.36)
mat_sole = make_material("MAT_Leather_Sole", "181512", 0.79, specular_ior_level=0.27)
mat_cowl = make_material("MAT_Cloth_HoodCowl", "242321", 0.94, specular_ior_level=0.22)
mat_glove = make_material("MAT_Leather_Gloves", "211B17", 0.74, specular_ior_level=0.30)
mat_hair = make_material("MAT_Hair_UnkemptBrown", "241D18", 0.80, specular_ior_level=0.28)
mat_eye_white = make_material("MAT_Eye_Sclera", "A99C88", 0.38, specular_ior_level=0.39)
mat_eye_iris = make_material("MAT_Eye_IrisBrown", "3A2A20", 0.30, specular_ior_level=0.40)
mat_eye_pupil = make_material("MAT_Eye_Pupil", "0E0D0C", 0.28, specular_ior_level=0.43)
mat_iron = make_material("MAT_Iron_DullBuckle", "4E4B46", 0.46, metallic=0.55, specular_ior_level=0.36)
mat_wood = make_material("MAT_Wood_CrossbowStock", "4A3020", 0.68, specular_ior_level=0.32)
mat_bolt_wood = make_material("MAT_Wood_BoltShaft", "6B4B2E", 0.69, specular_ior_level=0.30)
mat_feather = make_material("MAT_Bolt_Fletching", "7A7163", 0.88, specular_ior_level=0.22)
mat_ground = make_material("MAT_PREVIEW_Ground", "323232", 0.94, specular_ior_level=0.22)

# Procedural microstructure keeps the authoring render from reading as flat plastic.
add_surface_noise(mat_skin, 22.0, 0.055, 0.010, "95654F", "B27D62", detail=3.0)
add_surface_noise(mat_tunic, 42.0, 0.20, 0.012, "262421", "38342F", detail=5.0)
add_surface_noise(mat_tunic_patch, 34.0, 0.22, 0.015, "302D29", "443F38", detail=5.0)
add_surface_noise(mat_linen, 55.0, 0.22, 0.010, "625C54", "7D7569", detail=5.0)
add_surface_noise(mat_linen_dark, 48.0, 0.18, 0.009, "433F39", "5A544A", detail=4.0)
add_surface_noise(mat_trousers, 38.0, 0.18, 0.012, "282725", "3A3935", detail=4.5)
add_surface_noise(mat_cowl, 36.0, 0.24, 0.015, "1D1C1A", "302E2A", detail=5.0)
add_surface_noise(mat_leather, 15.0, 0.24, 0.018, "251C16", "3A2C21", detail=4.0)
add_surface_noise(mat_leather_light, 14.0, 0.22, 0.016, "392A20", "584331", detail=4.0)
add_surface_noise(mat_leather_edge, 12.0, 0.18, 0.014, "51402F", "755C43", detail=3.5)
add_surface_noise(mat_glove, 18.0, 0.20, 0.014, "18130F", "2A211B", detail=4.0)
add_surface_noise(mat_wood, 8.0, 0.16, 0.015, "382317", "5A3925", detail=3.5)

# Stable runtime hierarchy matching the existing Godot character contract.
root = make_empty("Root", (0.0, 0.0, 0.0))
root["asset_type"] = "character"
root["character_role"] = "mercenary_crossbowman"
root["height_m"] = 1.765
root["variant"] = "reference_v3"
root["blender_forward"] = "-Y"
root["godot_forward_after_gltf"] = "-Z"
root["license"] = "Original project asset"

visual_root = make_empty("VisualRoot", (0.0, 0.0, 0.0), root)
pelvis_pivot = make_empty("PelvisPivot", (0.0, 0.0, 0.89), visual_root)
torso_pivot = make_empty("TorsoPivot", (0.0, 0.0, 1.04), pelvis_pivot)
head_pivot = make_empty("HeadPivot", (0.0, 0.0, 1.49), torso_pivot)
back_pivot = make_empty("BackPivot", (0.0, 0.18, 1.18), torso_pivot)
back_weapon_pivot = make_empty("BackWeaponPivot", (0.0, 0.20, 1.19), back_pivot)
quiver_pivot = make_empty("QuiverPivot", (-0.03, 0.21, 1.10), back_pivot)
bolt_take_pivot = make_empty("BoltTakePivot", (0.15, 0.22, 1.45), quiver_pivot)
dagger_pivot = make_empty("DaggerPivot", (0.245, -0.005, 0.93), pelvis_pivot)

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

# Quilted gambeson base beneath the dark sleeveless coat.
tunic = make_oval_rings(
    "ClothQuiltedGambesonBody",
    [
        (0.620, 0.205, 0.123, 0.0, 0.003),
        (0.760, 0.220, 0.132, 0.0, 0.004),
        (0.940, 0.222, 0.133, 0.0, 0.005),
        (1.070, 0.214, 0.130, 0.0, 0.000),
        (1.235, 0.227, 0.143, 0.0, -0.005),
        (1.365, 0.233, 0.149, 0.0, -0.008),
        (1.415, 0.216, 0.143, 0.0, -0.005),
    ],
    24,
    mat_linen,
    parent=torso_pivot,
    bottom_jitter=(0.000, -0.004, 0.003, -0.006, -0.002, 0.004),
    smooth=True,
    category="Cloth",
    fold_strength=0.012,
    cap_top=False,
)

# Quilting seams on the visible front of the gambeson.
for seam_index, x_pos in enumerate((-0.120, -0.060, 0.0, 0.060, 0.120)):
    make_box_between(
        "ClothGambesonVerticalSeam{:02d}".format(seam_index + 1),
        (x_pos, -0.151, 0.650),
        (x_pos, -0.151, 1.360),
        0.003,
        0.002,
        mat_linen_dark,
        parent=torso_pivot,
        bevel=0.001,
        category="Cloth",
    )
for seam_index, z_pos in enumerate((0.700, 0.790, 0.880, 0.970, 1.060, 1.150, 1.240, 1.330)):
    make_box(
        "ClothGambesonHorizontalSeam{:02d}".format(seam_index + 1),
        (0.0, -0.151, z_pos),
        (0.350, 0.002, 0.003),
        mat_linen_dark,
        parent=torso_pivot,
        bevel=0.001,
        category="Cloth",
    )

# Dark sleeveless upper jerkin, open in a shallow V at the chest.
for panel_name, sign in (("L", 1.0), ("R", -1.0)):
    make_extruded_panel(
        "LeatherJerkinFront{}".format(panel_name),
        [
            (0.040 * sign, -0.220),
            (0.205 * sign, -0.205),
            (0.225 * sign, 0.155),
            (0.135 * sign, 0.220),
            (0.050 * sign, 0.080),
        ],
        (0.0, -0.153, 1.180),
        (1.0, 0.0, 0.0),
        (0.0, 0.0, 1.0),
        0.012,
        mat_tunic,
        parent=torso_pivot,
        category="Leather",
    )
make_extruded_panel(
    "LeatherJerkinBack",
    [(-0.220, -0.220), (0.220, -0.220), (0.225, 0.150), (0.150, 0.220), (-0.150, 0.220), (-0.225, 0.150)],
    (0.0, 0.153, 1.180),
    (1.0, 0.0, 0.0),
    (0.0, 0.0, 1.0),
    0.012,
    mat_tunic,
    parent=torso_pivot,
    category="Leather",
)
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    make_extruded_panel(
        "LeatherJerkinSide{}".format(side_name),
        [(-0.135, -0.220), (0.135, -0.220), (0.150, 0.150), (0.095, 0.220), (-0.095, 0.220), (-0.150, 0.150)],
        (0.220 * sign, 0.0, 1.180),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        0.012,
        mat_tunic,
        parent=torso_pivot,
        category="Leather",
    )
for rivet_index, (x_pos, z_pos) in enumerate(((-0.170, 1.080), (-0.170, 1.190), (-0.170, 1.300), (0.170, 1.080), (0.170, 1.190), (0.170, 1.300))):
    make_ellipsoid(
        "ArmorJerkinRivet{:02d}".format(rivet_index + 1),
        (x_pos, -0.162, z_pos),
        (0.006, 0.003, 0.006),
        mat_iron,
        torso_pivot,
        1,
        "Armor",
    )

# Four independently readable coat tails with deep front and rear splits.
front_tail_outline = [(0.090, 0.280), (0.255, 0.270), (0.270, -0.260), (0.235, -0.330), (0.195, -0.295), (0.155, -0.345), (0.110, -0.305)]
back_tail_outline = [(0.018, 0.280), (0.255, 0.270), (0.265, -0.270), (0.225, -0.340), (0.180, -0.300), (0.130, -0.350), (0.055, -0.305)]
for panel_name, sign in (("L", 1.0), ("R", -1.0)):
    make_extruded_panel(
        "ClothCoatTailFront{}".format(panel_name),
        [(u * sign, v) for u, v in front_tail_outline],
        (0.0, -0.148, 0.705),
        (1.0, 0.0, 0.0),
        (0.0, 0.0, 1.0),
        0.014,
        mat_tunic,
        parent=torso_pivot,
        category="Cloth",
    )

# Side gussets give the long coat believable volume in profile while preserving the deep splits.
side_tail_outline = [(-0.155, 0.280), (0.155, 0.280), (0.175, -0.245), (0.125, -0.335), (0.040, -0.305), (-0.045, -0.350), (-0.160, -0.270)]
for panel_name, sign in (("L", 1.0), ("R", -1.0)):
    make_extruded_panel(
        "ClothCoatTailSide{}".format(panel_name),
        side_tail_outline,
        (0.255 * sign, 0.0, 0.705),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        0.014,
        mat_tunic_patch,
        parent=torso_pivot,
        category="Cloth",
    )
    make_extruded_panel(
        "ClothCoatTailBack{}".format(panel_name),
        [(u * sign, v) for u, v in back_tail_outline],
        (0.0, 0.148, 0.705),
        (1.0, 0.0, 0.0),
        (0.0, 0.0, 1.0),
        0.014,
        mat_tunic_patch,
        parent=torso_pivot,
        category="Cloth",
    )

# Bright quilted center tab visible through the open coat.
make_extruded_panel(
    "ClothGambesonFrontTab",
    [(-0.105, 0.260), (0.105, 0.260), (0.105, -0.220), (0.065, -0.275), (0.010, -0.245), (-0.050, -0.280), (-0.105, -0.225)],
    (0.0, -0.157, 0.710),
    (1.0, 0.0, 0.0),
    (0.0, 0.0, 1.0),
    0.010,
    mat_linen,
    parent=torso_pivot,
    category="Cloth",
)
for seam_index, x_pos in enumerate((-0.070, 0.0, 0.070)):
    make_box_between(
        "ClothGambesonTabVerticalSeam{:02d}".format(seam_index + 1),
        (x_pos, -0.168, 0.485),
        (x_pos, -0.168, 0.945),
        0.003,
        0.002,
        mat_linen_dark,
        parent=torso_pivot,
        bevel=0.001,
        category="Cloth",
    )
for seam_index, z_pos in enumerate((0.520, 0.610, 0.700, 0.790, 0.880, 0.945)):
    make_box(
        "ClothGambesonTabHorizontalSeam{:02d}".format(seam_index + 1),
        (0.0, -0.168, z_pos),
        (0.196, 0.002, 0.003),
        mat_linen_dark,
        parent=torso_pivot,
        bevel=0.001,
        category="Cloth",
    )
for wear_index, wear_points in enumerate((
    ((-0.238, -0.169, 0.440), (-0.205, -0.169, 0.468), (-0.220, -0.169, 0.420)),
    ((0.205, -0.169, 0.505), (0.235, -0.169, 0.480), (0.226, -0.169, 0.530)),
    ((-0.190, -0.169, 0.610), (-0.165, -0.169, 0.595), (-0.180, -0.169, 0.635)),
)):
    make_triangle_patch(
        "ClothCoatWearHole{:02d}".format(wear_index + 1),
        wear_points,
        mat_sole,
        parent=torso_pivot,
        category="Cloth",
    )

# Thick lowered hood/cowl, the dominant shoulder silhouette in the reference.
make_oval_rings(
    "ClothHoodCowl",
    [
        (1.315, 0.270, 0.190),
        (1.345, 0.286, 0.202),
        (1.380, 0.270, 0.194),
        (1.410, 0.286, 0.188),
        (1.445, 0.232, 0.170),
        (1.480, 0.180, 0.145),
        (1.515, 0.108, 0.112),
        (1.535, 0.082, 0.097),
    ],
    28,
    mat_cowl,
    parent=torso_pivot,
    smooth=True,
    category="Cloth",
    fold_strength=0.028,
    cap_bottom=False,
    cap_top=False,
)
make_extruded_panel(
    "ClothHoodBackDrape",
    [(-0.155, 0.085), (0.155, 0.085), (0.150, -0.075), (0.080, -0.125), (0.0, -0.105), (-0.090, -0.130), (-0.150, -0.070)],
    (0.0, 0.198, 1.405),
    (1.0, 0.0, 0.0),
    (0.0, 0.0, 1.0),
    0.014,
    mat_cowl,
    parent=torso_pivot,
    category="Cloth",
)
make_extruded_panel(
    "ClothHoodFrontDrape",
    [(-0.220, 0.100), (0.220, 0.100), (0.180, -0.040), (0.100, -0.100), (0.0, -0.140), (-0.110, -0.110), (-0.190, -0.030)],
    (0.0, -0.196, 1.365),
    (1.0, 0.0, 0.0),
    (0.0, 0.0, 1.0),
    0.012,
    mat_cowl,
    parent=torso_pivot,
    category="Cloth",
)
for crease_index, crease_top in enumerate(((-0.165, -0.204, 1.430), (0.165, -0.204, 1.430))):
    make_box_between(
        "ClothHoodFrontCrease{:02d}".format(crease_index + 1),
        (0.0, -0.205, 1.238),
        crease_top,
        0.006,
        0.003,
        mat_tunic_patch,
        parent=torso_pivot,
        bevel=0.002,
        category="Cloth",
    )
for fold_index, (z_pos, major_radius, minor_radius, scale_x, scale_y) in enumerate((
    (1.395, 0.182, 0.026, 1.30, 1.00),
    (1.438, 0.148, 0.025, 1.32, 1.00),
    (1.478, 0.118, 0.023, 1.25, 1.00),
)):
    make_elliptical_torus(
        "ClothHoodFold{:02d}".format(fold_index + 1),
        (0.0, -0.008 * fold_index, z_pos),
        major_radius,
        minor_radius,
        mat_cowl,
        parent=torso_pivot,
        scale=(scale_x, scale_y, 1.0),
        category="Cloth",
    )

# Crossed load-bearing harness on both chest and back.
front_harness_segments = (
    ((-0.185, -0.207, 1.350), (0.150, -0.180, 1.015)),
    ((0.185, -0.207, 1.350), (-0.150, -0.180, 1.015)),
)
back_harness_segments = (
    ((-0.185, 0.207, 1.350), (0.150, 0.180, 1.015)),
    ((0.185, 0.207, 1.350), (-0.150, 0.180, 1.015)),
)
for harness_index, (point_a, point_b) in enumerate(front_harness_segments):
    make_box_between(
        "LeatherHarnessFront{:02d}".format(harness_index + 1),
        point_a,
        point_b,
        0.034,
        0.014,
        mat_leather_light,
        parent=torso_pivot,
        bevel=0.004,
        category="Leather",
    )
for harness_index, (point_a, point_b) in enumerate(back_harness_segments):
    make_box_between(
        "LeatherHarnessBack{:02d}".format(harness_index + 1),
        point_a,
        point_b,
        0.034,
        0.014,
        mat_leather_light,
        parent=back_pivot,
        bevel=0.004,
        category="Leather",
    )
make_box(
    "ArmorHarnessCenterPlate",
    (0.0, -0.215, 1.185),
    (0.054, 0.012, 0.052),
    mat_leather,
    parent=torso_pivot,
    rotation=(0.0, 0.0, math.radians(45.0)),
    bevel=0.005,
    category="Leather",
)
for rivet_index, (x_pos, z_pos) in enumerate(((-0.018, 1.185), (0.018, 1.185), (0.0, 1.205), (0.0, 1.165))):
    make_ellipsoid(
        "ArmorHarnessCenterRivet{:02d}".format(rivet_index + 1),
        (x_pos, -0.224, z_pos),
        (0.005, 0.003, 0.005),
        mat_iron,
        torso_pivot,
        1,
        "Armor",
    )

# Diagonal back quiver with a readable bundle of individual crossbow bolts.
quiver_lower = Vector((-0.205, 0.225, 0.805))
quiver_mid = Vector((-0.030, 0.230, 1.105))
quiver_upper = Vector((0.155, 0.232, 1.405))
quiver_direction = (quiver_upper - quiver_lower).normalized()
make_profile_limb(
    "LeatherQuiverBody",
    [quiver_lower, quiver_mid, quiver_upper],
    [(0.052, 0.043), (0.058, 0.047), (0.063, 0.051)],
    mat_leather,
    parent=quiver_pivot,
    segments=18,
    category="Leather",
    cap_ends=True,
)
make_cone_between(
    "LeatherQuiverMouthRim",
    quiver_upper - quiver_direction * 0.016,
    quiver_upper + quiver_direction * 0.018,
    0.067,
    0.067,
    mat_leather_edge,
    parent=quiver_pivot,
    vertices=20,
    category="Leather",
    cap_ends=False,
)
make_box_between(
    "LeatherQuiverReinforcement",
    quiver_lower + quiver_direction * 0.08,
    quiver_upper - quiver_direction * 0.08,
    0.018,
    0.010,
    mat_leather_edge,
    parent=quiver_pivot,
    bevel=0.003,
    category="Leather",
)
bolt_offsets = (
    (-0.030, -0.018, 0.00),
    (-0.010, -0.024, 0.03),
    (0.010, -0.020, -0.01),
    (0.030, -0.014, 0.04),
    (-0.023, 0.012, 0.02),
    (0.000, 0.016, 0.05),
    (0.023, 0.012, 0.01),
)
for bolt_index, (offset_x, offset_y, length_variation) in enumerate(bolt_offsets):
    offset = Vector((offset_x, offset_y, 0.0))
    shaft_start = quiver_upper - quiver_direction * 0.050 + offset
    shaft_end = quiver_upper + quiver_direction * (0.175 + length_variation) + offset
    make_cone_between(
        "WeaponBoltShaft{:02d}".format(bolt_index + 1),
        shaft_start,
        shaft_end,
        0.0042,
        0.0035,
        mat_bolt_wood,
        parent=quiver_pivot,
        vertices=8,
        category="Weapon",
    )
    make_box_between(
        "WeaponBoltFletching{:02d}".format(bolt_index + 1),
        shaft_end - quiver_direction * 0.050,
        shaft_end - quiver_direction * 0.006,
        0.018,
        0.003,
        mat_feather,
        parent=quiver_pivot,
        bevel=0.001,
        category="Weapon",
    )

# Double belts, sturdy buckles and asymmetric utility pouches.
make_oval_rings(
    "LeatherBelt",
    [(0.966, 0.220, 0.134), (1.000, 0.219, 0.133)],
    24,
    mat_leather,
    parent=pelvis_pivot,
    smooth=False,
    category="Leather",
)
make_oval_rings(
    "LeatherEquipmentBelt",
    [(0.910, 0.234, 0.142), (0.936, 0.232, 0.140)],
    24,
    mat_leather_light,
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
for pouch_name, pouch_location, pouch_dimensions, pouch_rotation in (
    ("R", (-0.225, -0.120, 0.885), (0.125, 0.075, 0.145), math.radians(7.0)),
    ("Center", (-0.085, -0.151, 0.895), (0.090, 0.055, 0.115), math.radians(-3.0)),
):
    make_box(
        "LeatherUtilityPouch{}".format(pouch_name),
        pouch_location,
        pouch_dimensions,
        mat_leather,
        parent=pelvis_pivot,
        rotation=(math.radians(-3.0), 0.0, pouch_rotation),
        bevel=0.010,
        category="Leather",
    )
    make_box(
        "LeatherUtilityPouch{}Flap".format(pouch_name),
        (pouch_location[0], pouch_location[1] - 0.041, pouch_location[2] + pouch_dimensions[2] * 0.25),
        (pouch_dimensions[0] * 0.92, 0.014, pouch_dimensions[2] * 0.42),
        mat_leather_edge,
        parent=pelvis_pivot,
        rotation=(math.radians(-8.0), 0.0, pouch_rotation),
        bevel=0.005,
        category="Leather",
    )
    make_box(
        "LeatherUtilityPouch{}Clasp".format(pouch_name),
        (pouch_location[0], pouch_location[1] - 0.050, pouch_location[2] + 0.005),
        (0.017, 0.007, 0.028),
        mat_iron,
        parent=pelvis_pivot,
        rotation=(0.0, 0.0, pouch_rotation),
        bevel=0.003,
        category="Armor",
    )

make_box(
    "LeatherEquipmentBeltBuckle",
    (0.105, -0.150, 0.923),
    (0.043, 0.014, 0.032),
    mat_iron,
    parent=pelvis_pivot,
    rotation=(0.0, 0.0, math.radians(-5.0)),
    bevel=0.004,
    category="Armor",
)

# Sheathed short sword / large dagger on the opposite hip.
dagger_sheath_top = Vector((0.270, -0.020, 0.885))
dagger_sheath_tip = Vector((0.325, -0.010, 0.535))
make_box_between(
    "WeaponDaggerScabbard",
    dagger_sheath_top,
    dagger_sheath_tip,
    0.052,
    0.030,
    mat_leather,
    parent=dagger_pivot,
    bevel=0.008,
    category="Weapon",
)
make_cone_between(
    "WeaponDaggerChape",
    dagger_sheath_tip - Vector((0.004, 0.0, 0.015)),
    dagger_sheath_tip + Vector((0.004, 0.0, 0.030)),
    0.024,
    0.027,
    mat_iron,
    parent=dagger_pivot,
    vertices=12,
    category="Weapon",
)
dagger_grip_bottom = Vector((0.266, -0.021, 0.900))
dagger_grip_top = Vector((0.250, -0.025, 1.010))
make_cone_between(
    "WeaponDaggerGrip",
    dagger_grip_bottom,
    dagger_grip_top,
    0.021,
    0.018,
    mat_leather_edge,
    parent=dagger_pivot,
    vertices=12,
    category="Weapon",
)
make_box(
    "WeaponDaggerGuard",
    (0.266, -0.022, 0.897),
    (0.115, 0.020, 0.020),
    mat_iron,
    parent=dagger_pivot,
    rotation=(0.0, math.radians(7.0), 0.0),
    bevel=0.005,
    category="Weapon",
)
make_ellipsoid(
    "WeaponDaggerPommel",
    dagger_grip_top + Vector((-0.003, 0.0, 0.012)),
    (0.023, 0.017, 0.026),
    mat_iron,
    dagger_pivot,
    2,
    "Weapon",
)
for hanger_index, z_pos in enumerate((0.865, 0.925)):
    make_box_between(
        "LeatherDaggerHanger{:02d}".format(hanger_index + 1),
        (0.205 + 0.020 * hanger_index, -0.020, 0.940),
        (0.270, -0.020, z_pos),
        0.018,
        0.010,
        mat_leather_light,
        parent=dagger_pivot,
        bevel=0.003,
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

    # Tall wrapped boot volume with the reference's characteristic cross-lacing.
    make_profile_limb(
        "ClothLegWrap{}".format(side_name),
        [
            Vector((0.102 * sign, -0.001, 0.115)),
            Vector((0.102 * sign, -0.001, 0.220)),
            Vector((0.102 * sign, 0.000, 0.335)),
            Vector((0.102 * sign, 0.000, 0.445)),
        ],
        [(0.054, 0.050), (0.060, 0.055), (0.067, 0.060), (0.070, 0.062)],
        mat_leather,
        parent=knee_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    for keeper_index, center_z in enumerate((0.140, 0.450)):
        make_cone_between(
            "LeatherBootKeeper{}{}".format(side_name, keeper_index + 1),
            (ankle.x, 0.0, center_z - 0.008),
            (ankle.x, 0.0, center_z + 0.008),
            0.058 if keeper_index == 0 else 0.072,
            0.059 if keeper_index == 0 else 0.073,
            mat_leather,
            parent=knee_pivot,
            vertices=18,
            category="Leather",
            cap_ends=False,
        )
    for lace_index, center_z in enumerate((0.175, 0.255, 0.335, 0.415)):
        lace_half_width = 0.045
        lace_half_height = 0.032
        lace_y = -0.064
        make_box_between(
            "LeatherBootLace{}{}A".format(side_name, lace_index + 1),
            (ankle.x - lace_half_width, lace_y, center_z - lace_half_height),
            (ankle.x + lace_half_width, lace_y, center_z + lace_half_height),
            0.009,
            0.006,
            mat_leather_light,
            parent=knee_pivot,
            bevel=0.002,
            category="Leather",
        )
        make_box_between(
            "LeatherBootLace{}{}B".format(side_name, lace_index + 1),
            (ankle.x + lace_half_width, lace_y - 0.002, center_z - lace_half_height),
            (ankle.x - lace_half_width, lace_y - 0.002, center_z + lace_half_height),
            0.009,
            0.006,
            mat_leather_light,
            parent=knee_pivot,
            bevel=0.002,
            category="Leather",
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

# Relaxed presentation pose with the arms hanging close to the coat, as in the reference sheet.
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    shoulder = Vector((0.205 * sign, 0.0, 1.405))
    sleeve_end = Vector((0.245 * sign, -0.003, 1.325))
    elbow = Vector((0.285 * sign, -0.012, 1.170))
    wrist = Vector((0.315 * sign, -0.020, 0.970))
    hand_center = Vector((0.323 * sign, -0.026, 0.875))

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
        [shoulder, Vector((0.228 * sign, -0.002, 1.372)), sleeve_end],
        [(0.047, 0.051), (0.060, 0.062), (0.055, 0.057)],
        mat_tunic,
        parent=arm_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    make_profile_limb(
        "ClothLinenUpperSleeve{}".format(side_name),
        [sleeve_end, Vector((0.266 * sign, -0.008, 1.255)), elbow],
        [(0.057, 0.059), (0.055, 0.057), (0.049, 0.052)],
        mat_linen,
        parent=arm_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    upper_sleeve_direction = (elbow - sleeve_end).normalized()
    for quilt_ring_index, t_value in enumerate((0.24, 0.52, 0.80)):
        ring_center = sleeve_end.lerp(elbow, t_value)
        ring_radius = 0.058 - 0.009 * t_value
        make_cone_between(
            "ClothSleeveQuiltRing{}{}".format(side_name, quilt_ring_index + 1),
            ring_center - upper_sleeve_direction * 0.004,
            ring_center + upper_sleeve_direction * 0.004,
            ring_radius,
            ring_radius,
            mat_linen_dark,
            parent=arm_pivot,
            vertices=18,
            category="Cloth",
            cap_ends=False,
        )
    for quilt_seam_index, x_offset in enumerate((-0.018, 0.018)):
        make_box_between(
            "ClothSleeveQuiltSeam{}{}".format(side_name, quilt_seam_index + 1),
            (sleeve_end.x + x_offset, -0.061, sleeve_end.z),
            (elbow.x + x_offset, -0.061, elbow.z),
            0.003,
            0.002,
            mat_linen_dark,
            parent=arm_pivot,
            bevel=0.001,
            category="Cloth",
        )
    make_profile_limb(
        "ClothLinenForearm{}".format(side_name),
        [elbow, Vector((0.300 * sign, -0.017, 1.075)), wrist],
        [(0.049, 0.052), (0.046, 0.049), (0.037, 0.040)],
        mat_linen,
        parent=elbow_pivot,
        segments=18,
        category="Cloth",
        cap_ends=False,
    )
    forearm_direction = (wrist - elbow).normalized()
    bracer_start = elbow + forearm_direction * 0.018
    bracer_end = wrist - forearm_direction * 0.020
    bracer_mid = (bracer_start + bracer_end) * 0.5
    make_profile_limb(
        "LeatherForearmGuard{}".format(side_name),
        [bracer_start, bracer_mid, bracer_end],
        [(0.052, 0.055), (0.048, 0.051), (0.041, 0.044)],
        mat_leather,
        parent=elbow_pivot,
        segments=18,
        category="Leather",
        cap_ends=False,
    )
    for bracer_lace_index, t_value in enumerate((0.20, 0.48, 0.76)):
        center = bracer_start.lerp(bracer_end, t_value)
        x_half = 0.036 + (1.0 - t_value) * 0.006
        z_half = 0.030
        lace_y = -0.064
        make_box_between(
            "LeatherForearmLace{}{}A".format(side_name, bracer_lace_index + 1),
            (center.x - x_half, lace_y, center.z - z_half),
            (center.x + x_half, lace_y, center.z + z_half),
            0.008,
            0.006,
            mat_leather_edge,
            parent=elbow_pivot,
            bevel=0.002,
            category="Leather",
        )
        make_box_between(
            "LeatherForearmLace{}{}B".format(side_name, bracer_lace_index + 1),
            (center.x + x_half, lace_y - 0.002, center.z - z_half),
            (center.x - x_half, lace_y - 0.002, center.z + z_half),
            0.008,
            0.006,
            mat_leather_edge,
            parent=elbow_pivot,
            bevel=0.002,
            category="Leather",
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
    make_ellipsoid_aligned(
        "LeatherFingerlessGlove{}".format(side_name),
        hand_center - hand_direction * 0.008,
        (0.037, 0.026, 0.045),
        hand_direction,
        mat_glove,
        parent=hand_pivot,
        category="Leather",
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

# Character-right presentation crossbow, held vertically beside the leg.
weapon_pivot = bpy.data.objects.get("WeaponPivot")
crossbow_pivot = make_empty("CrossbowPivot", (-0.340, -0.050, 0.875), weapon_pivot)
make_extruded_panel(
    "WeaponCrossbowWoodStock",
    [
        (-0.022, -0.425), (0.022, -0.425),
        (0.030, -0.165), (0.025, 0.100),
        (0.037, 0.200), (0.028, 0.425),
        (-0.028, 0.425), (-0.037, 0.200),
        (-0.025, 0.100), (-0.030, -0.165),
    ],
    (-0.340, -0.060, 0.550),
    (1.0, 0.0, 0.0),
    (0.0, 0.0, 1.0),
    0.048,
    mat_wood,
    parent=crossbow_pivot,
    category="Weapon",
)
make_box_between(
    "WeaponCrossbowTopRail",
    (-0.340, -0.089, 0.265),
    (-0.340, -0.089, 0.940),
    0.009,
    0.005,
    mat_iron,
    parent=crossbow_pivot,
    bevel=0.002,
    category="Weapon",
)
make_box(
    "WeaponCrossbowLockPlate",
    (-0.340, -0.090, 0.730),
    (0.090, 0.010, 0.120),
    mat_iron,
    parent=crossbow_pivot,
    bevel=0.006,
    category="Weapon",
)
make_box_between(
    "WeaponCrossbowHandGrip",
    (-0.334, -0.035, 0.905),
    (-0.366, -0.038, 0.810),
    0.038,
    0.032,
    mat_leather_edge,
    parent=crossbow_pivot,
    bevel=0.006,
    category="Weapon",
)
make_cone_between(
    "WeaponCrossbowTrigger",
    (-0.340, -0.094, 0.715),
    (-0.340, -0.125, 0.675),
    0.0055,
    0.0040,
    mat_iron,
    parent=crossbow_pivot,
    vertices=8,
    category="Weapon",
)

crossbow_center = Vector((-0.340, -0.060, 0.285))
crossbow_bow_points = (
    (crossbow_center, Vector((-0.450, -0.060, 0.265))),
    (Vector((-0.450, -0.060, 0.265)), Vector((-0.570, -0.060, 0.320))),
    (crossbow_center, Vector((-0.230, -0.060, 0.265))),
    (Vector((-0.230, -0.060, 0.265)), Vector((-0.110, -0.060, 0.320))),
)
for bow_index, (point_a, point_b) in enumerate(crossbow_bow_points):
    make_cone_between(
        "WeaponCrossbowProd{:02d}".format(bow_index + 1),
        point_a,
        point_b,
        0.0105,
        0.0090,
        mat_iron,
        parent=crossbow_pivot,
        vertices=10,
        category="Weapon",
    )
string_notch = Vector((-0.340, -0.102, 0.355))
for string_index, bow_tip in enumerate((Vector((-0.570, -0.060, 0.320)), Vector((-0.110, -0.060, 0.320)))):
    make_cone_between(
        "WeaponCrossbowString{:02d}".format(string_index + 1),
        bow_tip,
        string_notch,
        0.0015,
        0.0015,
        mat_sole,
        parent=crossbow_pivot,
        vertices=6,
        smooth=False,
        category="Weapon",
    )
for binding_index, z_pos in enumerate((0.280, 0.350)):
    make_box(
        "LeatherCrossbowBinding{:02d}".format(binding_index + 1),
        (-0.340, -0.086, z_pos),
        (0.075, 0.010, 0.020),
        mat_leather_light,
        parent=crossbow_pivot,
        bevel=0.003,
        category="Leather",
    )
stirrup_points = (
    Vector((-0.365, -0.060, 0.155)),
    Vector((-0.405, -0.060, 0.060)),
    Vector((-0.275, -0.060, 0.060)),
    Vector((-0.315, -0.060, 0.155)),
)
for stirrup_index in range(len(stirrup_points) - 1):
    make_cone_between(
        "WeaponCrossbowStirrup{:02d}".format(stirrup_index + 1),
        stirrup_points[stirrup_index],
        stirrup_points[stirrup_index + 1],
        0.0065,
        0.0065,
        mat_iron,
        parent=crossbow_pivot,
        vertices=8,
        category="Weapon",
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
        (1.505, 0.050, 0.060, 0.0, -0.008),
        (1.535, 0.073, 0.075, 0.0, -0.004),
        (1.585, 0.081, 0.085, 0.0, 0.000),
        (1.640, 0.082, 0.092, 0.0, 0.004),
        (1.700, 0.078, 0.090, 0.0, 0.006),
        (1.742, 0.050, 0.060, 0.0, 0.006),
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
for side_name, sign in (("L", 1.0), ("R", -1.0)):
    make_ellipsoid(
        "BodyCheek{}".format(side_name),
        (0.043 * sign, -0.078, 1.592),
        (0.034, 0.011, 0.028),
        mat_skin,
        head_pivot,
        2,
        "Body",
    )
    make_cone_between(
        "BodyLowerEyelid{}".format(side_name),
        (0.013 * sign, -0.091, 1.626),
        (0.050 * sign, -0.088, 1.625),
        0.0027,
        0.0018,
        mat_skin_shadow,
        parent=head_pivot,
        vertices=8,
        category="Body",
    )
mouth_center = Vector((0.0, -0.087, 1.560))
for mouth_index, mouth_corner in enumerate((Vector((-0.027, -0.085, 1.556)), Vector((0.027, -0.085, 1.556)))):
    make_cone_between(
        "BodyMouthLine{:02d}".format(mouth_index + 1),
        mouth_center,
        mouth_corner,
        0.0022,
        0.0015,
        mat_skin_shadow,
        parent=head_pivot,
        vertices=8,
        category="Body",
    )
make_cone_between(
    "BodyWeatheredCheekScar",
    (0.048, -0.093, 1.608),
    (0.061, -0.086, 1.579),
    0.0016,
    0.0010,
    mat_skin_shadow,
    parent=head_pivot,
    vertices=6,
    category="Body",
)

# Short facial hair following the jaw instead of a single beard sphere.
make_ellipsoid(
    "HairChinBeard",
    (0.0, -0.070, 1.528),
    (0.043, 0.024, 0.034),
    mat_hair,
    head_pivot,
    2,
    "Hair",
)
make_ellipsoid("HairJawL", (0.043, -0.066, 1.548), (0.030, 0.017, 0.030), mat_hair, head_pivot, 2, "Hair")
make_ellipsoid("HairJawR", (-0.043, -0.066, 1.548), (0.030, 0.017, 0.030), mat_hair, head_pivot, 2, "Hair")
make_ellipsoid("HairMoustacheL", (0.019, -0.086, 1.575), (0.023, 0.007, 0.006), mat_hair, head_pivot, 2, "Hair")
make_ellipsoid("HairMoustacheR", (-0.019, -0.086, 1.575), (0.023, 0.007, 0.006), mat_hair, head_pivot, 2, "Hair")
make_hair_cap(
    "HairUnkemptCap", (0.0, 0.010, 1.645), mat_hair, head_pivot,
    radius_x=0.089, radius_y=0.101, height=0.118,
)
for index, (root_point, tip_point) in enumerate((
    ((-0.066, -0.075, 1.724), (-0.078, -0.094, 1.662)),
    ((-0.032, -0.088, 1.750), (-0.025, -0.106, 1.680)),
    ((0.008, -0.092, 1.748), (0.015, -0.106, 1.687)),
    ((0.050, -0.083, 1.730), (0.058, -0.098, 1.671)),
    ((-0.083, -0.020, 1.700), (-0.098, -0.045, 1.625)),
    ((0.083, -0.020, 1.700), (0.098, -0.045, 1.625)),
    ((-0.087, 0.030, 1.680), (-0.103, 0.015, 1.602)),
    ((0.087, 0.030, 1.680), (0.103, 0.015, 1.602)),
    ((-0.055, 0.085, 1.690), (-0.060, 0.100, 1.600)),
    ((0.055, 0.085, 1.690), (0.060, 0.100, 1.600)),
)):
    root_point = Vector(root_point)
    tip_point = Vector(tip_point)
    lock_direction = tip_point - root_point
    make_ellipsoid_aligned(
        "HairForelock{}".format(index + 1),
        (root_point + tip_point) * 0.5,
        (0.018 if index < 4 else 0.015, 0.014, lock_direction.length * 0.53),
        lock_direction,
        mat_hair,
        parent=head_pivot,
        category="Hair",
    )
for index, (root_point, tip_point) in enumerate((
    ((-0.012, -0.010, 1.758), (-0.070, -0.060, 1.700)),
    ((0.018, -0.014, 1.758), (0.068, -0.070, 1.695)),
    ((-0.028, 0.012, 1.748), (-0.088, 0.025, 1.685)),
    ((0.030, 0.015, 1.750), (0.088, 0.040, 1.690)),
    ((-0.015, 0.035, 1.748), (-0.048, 0.094, 1.683)),
    ((0.018, 0.040, 1.748), (0.052, 0.096, 1.685)),
)):
    root_point = Vector(root_point)
    tip_point = Vector(tip_point)
    lock_direction = tip_point - root_point
    make_ellipsoid_aligned(
        "HairCrownLock{}".format(index + 1),
        (root_point + tip_point) * 0.5,
        (0.024, 0.019, lock_direction.length * 0.56),
        lock_direction,
        mat_hair,
        parent=head_pivot,
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

# Configure a selection-only GLB export. The actual export happens after visual QA,
# using temporary per-pivot merged meshes while the editable .blend stays modular.
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
    output_path = os.path.join(PREVIEW_DIR, "mercenary_crossbowman_{}.png".format(view_name))
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

# Merge tiny authored parts into articulation-friendly runtime groups for Godot.
# Original meshes remain untouched in the saved .blend and in the active scene.
export_collection = bpy.data.collections.new("EXPORT_OPTIMIZED_TEMP")
scene.collection.children.link(export_collection)
runtime_pivot_names = {
    "VisualRoot", "PelvisPivot", "TorsoPivot", "HeadPivot", "BackPivot",
    "QuiverPivot", "DaggerPivot", "CrossbowPivot",
    "ArmLPivot", "ElbowLPivot", "WristLPivot", "HandLPivot",
    "ArmRPivot", "ElbowRPivot", "WristRPivot", "HandRPivot",
    "LegLPivot", "KneeLPivot", "AnkleLPivot",
    "LegRPivot", "KneeRPivot", "AnkleRPivot",
}


def closest_runtime_pivot(obj):
    candidate = obj.parent
    while candidate is not None:
        if candidate.name in runtime_pivot_names:
            return candidate
        candidate = candidate.parent
    return visual_root


runtime_groups = {}
for authored_mesh in mesh_objects:
    pivot = closest_runtime_pivot(authored_mesh)
    runtime_groups.setdefault(pivot, []).append(authored_mesh)

optimized_meshes = []
for pivot, authored_group in runtime_groups.items():
    duplicates = []
    for authored_mesh in authored_group:
        duplicate = authored_mesh.copy()
        duplicate.data = authored_mesh.data.copy()
        duplicate.animation_data_clear()
        duplicate.parent = None
        duplicate.matrix_world = authored_mesh.matrix_world.copy()
        export_collection.objects.link(duplicate)
        duplicates.append(duplicate)

    bpy.ops.object.select_all(action="DESELECT")
    for duplicate in duplicates:
        duplicate.select_set(True)
    bpy.context.view_layer.objects.active = duplicates[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = "OPT_{}Mesh".format(pivot.name)
    merged["game_asset"] = True
    merged["runtime_group"] = pivot.name
    parent_keep_world(merged, pivot)
    optimized_meshes.append(merged)

bpy.ops.object.select_all(action="DESELECT")
for obj in asset_collection.objects:
    if obj.type == "EMPTY":
        obj.select_set(True)
for obj in optimized_meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(**gltf_args)

optimized_mesh_object_count = len(optimized_meshes)
optimized_material_primitive_hint = sum(len(obj.data.materials) for obj in optimized_meshes)
for obj in list(optimized_meshes):
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.data.collections.remove(export_collection)

result = {
    "status": "ok",
    "asset": "mercenary_crossbowman_3d",
    "height_m": 1.765,
    "mesh_objects": len(mesh_objects),
    "triangle_count_authored": triangle_count,
    "runtime_mesh_groups": optimized_mesh_object_count,
    "runtime_material_primitive_hint": optimized_material_primitive_hint,
    "blend_path": BLEND_PATH,
    "glb_path": GLB_PATH,
    "preview_paths": preview_paths,
    "root": root.name,
    "forward_blender": "-Y",
    "forward_godot": "-Z",
}
