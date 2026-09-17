import bpy
import math
import os
import random
from mathutils import Vector


STAGING_DIR = "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_mercenary_crossbowman_photoreal"
TEXTURE_DIR = os.path.join(STAGING_DIR, "textures")
PREVIEW_DIR = os.path.join(STAGING_DIR, "previews")
BASE_BLEND = os.path.join(
    STAGING_DIR,
    "resources",
    "human-base-meshes-bundle-v1.4.1",
    "human_base_meshes_bundle.blend",
)
BLEND_PATH = os.path.join(STAGING_DIR, "mercenary_crossbowman_photoreal_3d.blend")
GLB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(STAGING_DIR)),
    "godot-game",
    "assets",
    "3d",
    "dark_fantasy",
    "mercenary_crossbowman_photoreal_3d.glb",
)
BODY_SCALE = 1.0770
BODY_SOURCE_X = -2.264302
RNG = random.Random(48271)

os.makedirs(PREVIEW_DIR, exist_ok=True)
os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)


def srgb_channel_to_linear(value):
    value = value / 255.0
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def color_from_hex(value, alpha=1.0):
    value = value.lstrip("#")
    return (
        srgb_channel_to_linear(int(value[0:2], 16)),
        srgb_channel_to_linear(int(value[2:4], 16)),
        srgb_channel_to_linear(int(value[4:6], 16)),
        alpha,
    )


def set_input(node, name, value):
    socket = node.inputs.get(name)
    if socket is not None:
        socket.default_value = value


def set_smooth(obj):
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True


def assign_material(obj, material):
    if hasattr(obj.data, "materials"):
        obj.data.materials.clear()
        obj.data.materials.append(material)


def move_to_collection(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def parent_keep_world(obj, parent):
    bpy.context.view_layer.update()
    matrix = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = matrix


def tag(obj, category):
    obj["part_category"] = category
    obj["game_asset"] = True


def load_image(filename, non_color=False):
    path = os.path.join(TEXTURE_DIR, filename)
    image = bpy.data.images.load(path, check_existing=True)
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    return image


def make_simple_material(
    name,
    hex_color,
    roughness=0.5,
    metallic=0.0,
    subsurface=0.0,
    transmission=0.0,
):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = color_from_hex(hex_color)
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    set_input(bsdf, "Base Color", color_from_hex(hex_color))
    set_input(bsdf, "Roughness", roughness)
    set_input(bsdf, "Metallic", metallic)
    set_input(bsdf, "Subsurface Weight", subsurface)
    set_input(bsdf, "Transmission Weight", transmission)
    set_input(bsdf, "IOR", 1.42)
    return material


def make_skin_material():
    material = bpy.data.materials.new("MAT_Skin_Weathered_Photoreal")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    set_input(bsdf, "Roughness", 0.48)
    set_input(bsdf, "Specular IOR Level", 0.34)
    set_input(bsdf, "Subsurface Weight", 0.115)
    set_input(bsdf, "Subsurface Radius", (1.0, 0.42, 0.20))
    texcoord = nodes.new("ShaderNodeTexCoord")
    macro = nodes.new("ShaderNodeTexNoise")
    macro.inputs["Scale"].default_value = 4.5
    macro.inputs["Detail"].default_value = 5.0
    macro.inputs["Roughness"].default_value = 0.68
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.18
    ramp.color_ramp.elements[0].color = color_from_hex("4C3028")
    middle = ramp.color_ramp.elements.new(0.52)
    middle.color = color_from_hex("76503F")
    ramp.color_ramp.elements[-1].position = 0.86
    ramp.color_ramp.elements[-1].color = color_from_hex("A07963")
    pores = nodes.new("ShaderNodeTexNoise")
    pores.inputs["Scale"].default_value = 620.0
    pores.inputs["Detail"].default_value = 2.0
    pores.inputs["Roughness"].default_value = 0.72
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.22
    bump.inputs["Distance"].default_value = 0.00020
    links.new(texcoord.outputs["Generated"], macro.inputs["Vector"])
    links.new(macro.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(texcoord.outputs["Generated"], pores.inputs["Vector"])
    links.new(pores.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def make_texture_material(
    name,
    tint,
    diffuse_file,
    rough_file,
    normal_file,
    mapping_scale=(4.0, 4.0, 4.0),
    rough_min=0.38,
    rough_max=0.92,
    normal_strength=0.45,
    sheen=0.0,
    quilted=False,
):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    set_input(bsdf, "Roughness", 0.72)
    set_input(bsdf, "Specular IOR Level", 0.28)
    set_input(bsdf, "Sheen Weight", sheen)
    texcoord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = mapping_scale
    links.new(texcoord.outputs["Generated"], mapping.inputs["Vector"])

    diffuse = nodes.new("ShaderNodeTexImage")
    diffuse.image = load_image(diffuse_file)
    diffuse.projection = "BOX"
    diffuse.projection_blend = 0.22
    multiply = nodes.new("ShaderNodeMixRGB")
    multiply.blend_type = "MULTIPLY"
    multiply.inputs[0].default_value = 1.0
    multiply.inputs[2].default_value = color_from_hex(tint)
    links.new(mapping.outputs["Vector"], diffuse.inputs["Vector"])
    links.new(diffuse.outputs["Color"], multiply.inputs[1])
    links.new(multiply.outputs["Color"], bsdf.inputs["Base Color"])

    rough = nodes.new("ShaderNodeTexImage")
    rough.image = load_image(rough_file, non_color=True)
    rough.projection = "BOX"
    rough.projection_blend = 0.22
    remap = nodes.new("ShaderNodeMapRange")
    remap.inputs["To Min"].default_value = rough_min
    remap.inputs["To Max"].default_value = rough_max
    links.new(mapping.outputs["Vector"], rough.inputs["Vector"])
    links.new(rough.outputs["Color"], remap.inputs["Value"])
    links.new(remap.outputs["Result"], bsdf.inputs["Roughness"])

    normal = nodes.new("ShaderNodeTexImage")
    normal.image = load_image(normal_file, non_color=True)
    normal.projection = "BOX"
    normal.projection_blend = 0.22
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = normal_strength
    links.new(mapping.outputs["Vector"], normal.inputs["Vector"])
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])

    if quilted:
        wave_x = nodes.new("ShaderNodeTexWave")
        wave_x.wave_type = "BANDS"
        wave_x.bands_direction = "X"
        wave_x.inputs["Scale"].default_value = 18.0
        wave_x.inputs["Distortion"].default_value = 1.2
        wave_z = nodes.new("ShaderNodeTexWave")
        wave_z.wave_type = "BANDS"
        wave_z.bands_direction = "Z"
        wave_z.inputs["Scale"].default_value = 14.0
        wave_z.inputs["Distortion"].default_value = 1.0
        cut_x = nodes.new("ShaderNodeMath")
        cut_x.operation = "GREATER_THAN"
        cut_x.inputs[1].default_value = 0.86
        cut_z = nodes.new("ShaderNodeMath")
        cut_z.operation = "GREATER_THAN"
        cut_z.inputs[1].default_value = 0.86
        combine = nodes.new("ShaderNodeMath")
        combine.operation = "MAXIMUM"
        seam_bump = nodes.new("ShaderNodeBump")
        seam_bump.inputs["Strength"].default_value = 0.38
        seam_bump.inputs["Distance"].default_value = 0.00135
        seam_bump.invert = True
        links.new(mapping.outputs["Vector"], wave_x.inputs["Vector"])
        links.new(mapping.outputs["Vector"], wave_z.inputs["Vector"])
        links.new(wave_x.outputs["Fac"], cut_x.inputs[0])
        links.new(wave_z.outputs["Fac"], cut_z.inputs[0])
        links.new(cut_x.outputs[0], combine.inputs[0])
        links.new(cut_z.outputs[0], combine.inputs[1])
        links.new(combine.outputs[0], seam_bump.inputs["Height"])
        links.new(normal_map.outputs["Normal"], seam_bump.inputs["Normal"])
        links.new(seam_bump.outputs["Normal"], bsdf.inputs["Normal"])
    else:
        links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])

    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    material.diffuse_color = color_from_hex(tint)
    return material


def make_hair_material():
    material = bpy.data.materials.new("MAT_Hair_DarkBrown_Strands")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    set_input(bsdf, "Base Color", color_from_hex("160D09"))
    set_input(bsdf, "Roughness", 0.52)
    set_input(bsdf, "Specular IOR Level", 0.42)
    set_input(bsdf, "Anisotropic IOR Level", 0.28)
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9.0
    noise.inputs["Detail"].default_value = 3.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = color_from_hex("070403")
    ramp.color_ramp.elements[-1].color = color_from_hex("3A2114")
    coord = nodes.new("ShaderNodeTexCoord")
    links.new(coord.outputs["Generated"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def make_procedural_fabric(name, hex_color, roughness, sheen, micro_scale=320.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    base = color_from_hex(hex_color)
    set_input(bsdf, "Roughness", roughness)
    set_input(bsdf, "Specular IOR Level", 0.22)
    set_input(bsdf, "Sheen Weight", sheen)
    texcoord = nodes.new("ShaderNodeTexCoord")
    color_noise = nodes.new("ShaderNodeTexNoise")
    color_noise.inputs["Scale"].default_value = 7.0
    color_noise.inputs["Detail"].default_value = 5.0
    color_noise.inputs["Roughness"].default_value = 0.72
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = tuple(channel * 0.62 for channel in base[:3]) + (1.0,)
    ramp.color_ramp.elements[0].position = 0.18
    ramp.color_ramp.elements[-1].color = tuple(min(1.0, channel * 1.28 + 0.008) for channel in base[:3]) + (1.0,)
    ramp.color_ramp.elements[-1].position = 0.84
    micro = nodes.new("ShaderNodeTexNoise")
    micro.inputs["Scale"].default_value = micro_scale
    micro.inputs["Detail"].default_value = 2.0
    micro.inputs["Roughness"].default_value = 0.78
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.20
    bump.inputs["Distance"].default_value = 0.00032
    links.new(texcoord.outputs["Generated"], color_noise.inputs["Vector"])
    links.new(color_noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(texcoord.outputs["Generated"], micro.inputs["Vector"])
    links.new(micro.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    material.diffuse_color = base
    return material


def make_empty(name, location=(0.0, 0.0, 0.0), parent=None, size=0.05):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = size
    asset_collection.objects.link(obj)
    obj.location = location
    if parent is not None:
        parent_keep_world(obj, parent)
    return obj


def make_box(name, location, dimensions, material, rotation=(0.0, 0.0, 0.0), bevel=0.004,
             category="Equipment", parent=None, collection=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        mod = obj.modifiers.new("RoundedEdges", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
    assign_material(obj, material)
    move_to_collection(obj, collection or asset_collection)
    if parent is not None:
        parent_keep_world(obj, parent)
    set_smooth(obj)
    tag(obj, category)
    return obj


def make_box_between(name, a, b, width, thickness, material, bevel=0.003,
                     category="Equipment", parent=None):
    a = Vector(a)
    b = Vector(b)
    direction = b - a
    obj = make_box(
        name,
        (a + b) * 0.5,
        (width, thickness, direction.length),
        material,
        bevel=bevel,
        category=category,
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    if parent is not None:
        parent_keep_world(obj, parent)
    return obj


def make_uv_sphere(name, location, scale, material, category="Body", parent=None,
                   segments=48, rings=24):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1.0,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    assign_material(obj, material)
    move_to_collection(obj, asset_collection)
    set_smooth(obj)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag(obj, category)
    return obj


def make_cone_between(name, a, b, radius_a, radius_b, material, vertices=32,
                      category="Equipment", parent=None, cap=True):
    a = Vector(a)
    b = Vector(b)
    direction = b - a
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_a,
        radius2=radius_b,
        depth=direction.length,
        end_fill_type="NGON" if cap else "NOTHING",
        location=(a + b) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    assign_material(obj, material)
    move_to_collection(obj, asset_collection)
    set_smooth(obj)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag(obj, category)
    return obj


def make_torus(name, location, major_radius, minor_radius, material, scale=(1, 1, 1),
               rotation=(0, 0, 0), category="Cloth", parent=None, major_segments=64,
               minor_segments=16):
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
    assign_material(obj, material)
    move_to_collection(obj, asset_collection)
    set_smooth(obj)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag(obj, category)
    return obj


def make_profile_tube(name, points, radii, material, segments=32, cap_start=True,
                      cap_end=True, category="Equipment", parent=None):
    points = [Vector(point) for point in points]
    vertices = []
    for point_index, point in enumerate(points):
        if point_index == 0:
            tangent = (points[1] - point).normalized()
        elif point_index == len(points) - 1:
            tangent = (point - points[-2]).normalized()
        else:
            tangent = (points[point_index + 1] - points[point_index - 1]).normalized()
        reference = Vector((0.0, 1.0, 0.0))
        if abs(tangent.dot(reference)) > 0.92:
            reference = Vector((1.0, 0.0, 0.0))
        axis_a = reference.cross(tangent).normalized()
        axis_b = tangent.cross(axis_a).normalized()
        radius_a, radius_b = radii[point_index]
        for segment in range(segments):
            angle = math.tau * segment / segments
            vertices.append(point + axis_a * math.cos(angle) * radius_a + axis_b * math.sin(angle) * radius_b)
    faces = []
    for ring in range(len(points) - 1):
        a0 = ring * segments
        b0 = (ring + 1) * segments
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append((a0 + segment, a0 + nxt, b0 + nxt, b0 + segment))
    if cap_start:
        faces.append(tuple(reversed(range(segments))))
    if cap_end:
        start = (len(points) - 1) * segments
        faces.append(tuple(start + i for i in range(segments)))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag(obj, category)
    return obj


def make_elliptic_loft(name, rings, material, segments=64, folds=0.0,
                       cap_start=False, cap_end=False, solidify=0.0,
                       subdivision=1, category="Cloth", parent=None):
    vertices = []
    for ring_index, ring in enumerate(rings):
        z, rx, ry = ring[:3]
        cx = ring[3] if len(ring) > 3 else 0.0
        cy = ring[4] if len(ring) > 4 else 0.0
        ring_weight = 1.0 - ring_index / max(1, len(rings) - 1)
        for segment in range(segments):
            angle = math.tau * segment / segments
            fold = 1.0 + folds * (0.45 + 0.55 * ring_weight) * (
                0.60 * math.sin(7.0 * angle + 0.31) +
                0.40 * math.sin(11.0 * angle - 0.24)
            )
            vertices.append((cx + math.cos(angle) * rx * fold, cy + math.sin(angle) * ry * fold, z))
    faces = []
    for ring in range(len(rings) - 1):
        a0 = ring * segments
        b0 = (ring + 1) * segments
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append((a0 + segment, a0 + nxt, b0 + nxt, b0 + segment))
    if cap_start:
        faces.append(tuple(reversed(range(segments))))
    if cap_end:
        start = (len(rings) - 1) * segments
        faces.append(tuple(start + i for i in range(segments)))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    if subdivision:
        mod = obj.modifiers.new("TailoredSubdivision", "SUBSURF")
        mod.subdivision_type = "CATMULL_CLARK"
        mod.levels = subdivision
        mod.render_levels = subdivision
    if solidify:
        mod = obj.modifiers.new("ClothThickness", "SOLIDIFY")
        mod.thickness = solidify
        mod.offset = 0.0
    if parent is not None:
        parent_keep_world(obj, parent)
    tag(obj, category)
    return obj


def make_draped_panel(name, orientation, u_min, u_max, z_top, z_bottom, plane,
                      outward_sign, material, phase, category="Cloth", parent=None,
                      u_segments=24, v_segments=40):
    vertices = []
    for v_index in range(v_segments + 1):
        v = v_index / v_segments
        eased = v * v * (3.0 - 2.0 * v)
        for u_index in range(u_segments + 1):
            u_t = u_index / u_segments
            u = u_min + (u_max - u_min) * u_t
            hem_noise = 0.012 * math.sin(17.0 * u + phase) + 0.008 * math.sin(31.0 * u - phase)
            local_bottom = z_bottom + hem_noise
            z = z_top + (local_bottom - z_top) * v
            broad = math.sin(math.pi * u_t)
            fold = eased * (
                0.010 * math.sin(4.0 * math.pi * u_t + phase) +
                0.006 * math.sin(9.0 * math.pi * u_t - phase)
            )
            sway = 0.012 * broad * math.sin(math.pi * v + phase)
            if orientation == "X":
                x = u + sway * (1.0 if u >= 0.0 else -1.0)
                y = plane + outward_sign * fold
            else:
                x = plane + outward_sign * fold
                y = u + sway * (1.0 if u >= 0.0 else -1.0)
            vertices.append((x, y, z))
    faces = []
    stride = u_segments + 1
    for v_index in range(v_segments):
        for u_index in range(u_segments):
            a = v_index * stride + u_index
            faces.append((a, a + 1, a + 1 + stride, a + stride))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    sub = obj.modifiers.new("DrapeSubdivision", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    solid = obj.modifiers.new("WoolThickness", "SOLIDIFY")
    solid.thickness = 0.0055
    solid.offset = 0.0
    if parent is not None:
        parent_keep_world(obj, parent)
    tag(obj, category)
    return obj


def make_poly_curve(name, polylines, material, bevel_depth, category="Hair", parent=None,
                    bevel_resolution=2, convert=True):
    curve = bpy.data.curves.new(name + "Curve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = bevel_resolution
    curve.fill_mode = "FULL"
    curve.use_fill_caps = True
    for points in polylines:
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for index, point in enumerate(points):
            spline.points[index].co = (*point, 1.0)
            spline.points[index].radius = max(0.18, 1.0 - 0.78 * index / max(1, len(points) - 1))
    obj = bpy.data.objects.new(name, curve)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    if parent is not None:
        parent_keep_world(obj, parent)
    tag(obj, category)
    if convert:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
        obj = bpy.context.object
        obj.name = name
        set_smooth(obj)
        tag(obj, category)
    return obj


def subset_shell(name, body_obj, keep_face, offset, material, solidify=0.004,
                 subdivision=1, category="Cloth"):
    body_obj.data.update()
    used = {}
    vertices = []
    faces = []
    for polygon in body_obj.data.polygons:
        center = sum((body_obj.data.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
        if not keep_face(center):
            continue
        face = []
        for index in polygon.vertices:
            if index not in used:
                vertex = body_obj.data.vertices[index]
                used[index] = len(vertices)
                vertices.append(vertex.co + vertex.normal * offset)
            face.append(used[index])
        faces.append(tuple(face))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    obj.matrix_world = body_obj.matrix_world.copy()
    assign_material(obj, material)
    set_smooth(obj)
    if subdivision:
        sub = obj.modifiers.new("GarmentSubdivision", "SUBSURF")
        sub.levels = subdivision
        sub.render_levels = subdivision
    if solidify:
        solid = obj.modifiers.new("GarmentThickness", "SOLIDIFY")
        solid.thickness = solidify
        solid.offset = 0.0
    tag(obj, category)
    return obj


def make_scalp_cap(center, radii, material, parent=None):
    segments = 64
    rings = 16
    vertices = []
    for ring in range(rings + 1):
        t = ring / rings
        for segment in range(segments):
            phi = math.tau * segment / segments
            front = max(0.0, -math.sin(phi))
            theta_max = 1.52 - 0.13 * front
            theta = 0.02 + t * theta_max
            vertices.append((
                center.x + radii.x * math.sin(theta) * math.cos(phi),
                center.y + radii.y * math.sin(theta) * math.sin(phi),
                center.z + radii.z * math.cos(theta),
            ))
    faces = []
    for ring in range(rings):
        a0 = ring * segments
        b0 = (ring + 1) * segments
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append((a0 + segment, b0 + segment, b0 + nxt, a0 + nxt))
    mesh = bpy.data.meshes.new("HairScalpCapMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("HairScalpCap", mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    sub = obj.modifiers.new("ScalpSubdivision", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    if parent is not None:
        parent_keep_world(obj, parent)
    tag(obj, "Hair")
    return obj


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Clean the dedicated Blender scene.
scene = bpy.context.scene
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    bpy.data.collections.remove(collection)
for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
    for datablock in list(datablocks):
        if datablock.users == 0:
            datablocks.remove(datablock)

asset_collection = bpy.data.collections.new("CHR_MercenaryCrossbowman_Photoreal")
preview_collection = bpy.data.collections.new("PREVIEW_STUDIO")
scene.collection.children.link(asset_collection)
scene.collection.children.link(preview_collection)
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

character_root = make_empty("CHARACTER_ROOT", (0.0, 0.0, 0.0), size=0.08)
character_root["asset_type"] = "character"
character_root["character_role"] = "mercenary_crossbowman"
character_root["variant"] = "photoreal_reference_v4"
character_root["height_m"] = 1.82
character_root["blender_forward"] = "-Y"
character_root["godot_forward_after_gltf"] = "-Z"
character_root["license"] = "Original clothing/equipment; Blender Human Base Meshes CC0; Poly Haven CC0 textures"
root_alias = make_empty("Root", (0.0, 0.0, 0.0), character_root, size=0.065)
visual_root = make_empty("VisualRoot", (0.0, 0.0, 0.0), root_alias, size=0.05)
torso_pivot = make_empty("TorsoPivot", (0.0, 0.0, 1.14), visual_root)
head_pivot = make_empty("HeadPivot", (0.0, 0.0, 1.64), torso_pivot)
back_pivot = make_empty("BackPivot", (0.0, 0.20, 1.18), torso_pivot)
quiver_pivot = make_empty("QuiverPivot", (-0.02, 0.26, 1.12), back_pivot)
dagger_pivot = make_empty("DaggerPivot", (0.30, 0.0, 0.92), visual_root)
crossbow_pivot = make_empty("CrossbowPivot", (-0.37, -0.12, 0.83), visual_root)

# Append the official Blender CC0 realistic male body and eyes.
with bpy.data.libraries.load(BASE_BLEND, link=False) as (data_from, data_to):
    if "Body Male - Realistic" not in data_from.collections:
        raise RuntimeError("Body Male - Realistic collection missing from official base bundle")
    data_to.collections = ["Body Male - Realistic"]
human_collection = data_to.collections[0]
human_collection.name = "HUMAN_BASE_CC0_REALISTIC_MALE"
asset_collection.children.link(human_collection)
human_root = make_empty("HumanBaseRoot", (0.0, 0.0, 0.0), visual_root, size=0.055)
for obj in list(human_collection.objects):
    if obj.parent is None:
        parent_keep_world(obj, human_root)
human_root.location = (-BODY_SOURCE_X * BODY_SCALE, 0.0, 0.0)
human_root.scale = (BODY_SCALE, BODY_SCALE, BODY_SCALE)
bpy.context.view_layer.update()

body = next((obj for obj in human_collection.objects if obj.name.startswith("GEO-body_male_realistic") and ".eye." not in obj.name), None)
if body is None:
    raise RuntimeError("realistic male body object could not be found")
body.name = "Body_Male_Realistic_CC0"
body["source"] = "Blender Human Base Meshes v1.4.1"
body["license"] = "CC0"

# Relax the A-pose to a guarded, arms-down neutral pose and make the face slightly more rugged.
body_multires = next((modifier for modifier in body.modifiers if modifier.type == "MULTIRES"), None)
if body_multires is not None:
    body_multires.levels = 1
    body_multires.render_levels = 2
for vertex in body.data.vertices:
    co = vertex.co.copy()
    side = 1.0 if co.x >= 0.0 else -1.0
    lateral = abs(co.x)
    arm_weight = max(0.0, min(1.0, (lateral - 0.165) / 0.105))
    arm_weight *= max(0.0, min(1.0, (1.50 - co.z) / 0.18))
    if arm_weight > 0.0 and 0.66 < co.z < 1.50:
        pivot = Vector((0.175 * side, 0.0, 1.405))
        angle = math.radians(18.0 * side * arm_weight)
        delta = co - pivot
        rotated = Vector((
            math.cos(angle) * delta.x + math.sin(angle) * delta.z,
            delta.y,
            -math.sin(angle) * delta.x + math.cos(angle) * delta.z,
        ))
        co = pivot + rotated
    # Wider, stronger jaw and subtle brow/nose definition.
    if 1.465 < co.z < 1.545 and co.y < -0.025 and abs(co.x) < 0.095:
        weight = 1.0 - abs(co.z - 1.505) / 0.040
        co.x *= 1.0 + 0.055 * max(0.0, weight)
        co.y -= 0.0030 * max(0.0, weight)
    if 1.565 < co.z < 1.615 and co.y < -0.055 and abs(co.x) < 0.065:
        co.y -= 0.0020
    if 1.535 < co.z < 1.605 and co.y < -0.070 and abs(co.x) < 0.026:
        co.y -= 0.0022
    vertex.co = co
body.data.update()
set_smooth(body)

# Photoreal materials.
mat_skin = make_skin_material()
mat_eye = make_simple_material("MAT_Eye_Sclera_Warm", "A99E92", 0.30)
mat_iris = make_simple_material("MAT_Eye_Iris_HazelBrown", "342218", 0.27)
mat_pupil = make_simple_material("MAT_Eye_Pupil", "050403", 0.18)
mat_cornea = make_simple_material("MAT_Eye_Cornea", "EEF3F0", 0.03, transmission=1.0)
set_input(mat_cornea.node_tree.nodes.get("Principled BSDF"), "Coat Weight", 0.75)
set_input(mat_cornea.node_tree.nodes.get("Principled BSDF"), "IOR", 1.376)
mat_linen = make_procedural_fabric("MAT_Gambeson_RoughLinen_Quilted", "6A5A49", 0.86, 0.18, 420.0)
mat_dark_cloth = make_procedural_fabric("MAT_OuterCoat_CharcoalWool", "191A19", 0.91, 0.24, 300.0)
mat_cowl = make_procedural_fabric("MAT_Cowl_HeavyBlackWool", "101110", 0.94, 0.26, 260.0)
mat_trousers = make_procedural_fabric("MAT_Trousers_WornCharcoal", "242421", 0.90, 0.15, 360.0)
mat_leather = make_texture_material(
    "MAT_Leather_DarkWorn_PBR",
    "4A3324",
    "brown_leather_albedo_2k.jpg",
    "brown_leather_rough_2k.jpg",
    "brown_leather_nor_gl_2k.jpg",
    mapping_scale=(3.0, 3.0, 4.0),
    rough_min=0.38,
    rough_max=0.82,
    normal_strength=0.55,
)
mat_leather_light = make_texture_material(
    "MAT_Leather_Harness_Worn_PBR",
    "765238",
    "brown_leather_albedo_2k.jpg",
    "brown_leather_rough_2k.jpg",
    "brown_leather_nor_gl_2k.jpg",
    mapping_scale=(4.0, 3.0, 5.0),
    rough_min=0.34,
    rough_max=0.78,
    normal_strength=0.48,
)
mat_wood = make_texture_material(
    "MAT_Crossbow_WornWood_PBR",
    "6A3F25",
    "wood_table_worn_diff_2k.jpg",
    "wood_table_worn_rough_2k.jpg",
    "wood_table_worn_nor_gl_2k.jpg",
    mapping_scale=(2.5, 2.5, 5.0),
    rough_min=0.34,
    rough_max=0.78,
    normal_strength=0.48,
)
mat_iron = make_simple_material("MAT_Iron_Blackened", "343638", 0.32, metallic=0.92)
mat_iron_worn = make_simple_material("MAT_Iron_EdgeWear", "6B6A65", 0.24, metallic=0.96)
mat_string = make_simple_material("MAT_Hemp_Bowstring", "625443", 0.84)
mat_feather = make_simple_material("MAT_Bolt_Fletching", "8A8174", 0.90)
mat_hair = make_hair_material()
mat_hair_cap = make_simple_material("MAT_Hair_ScalpMass", "080503", 0.72)
mat_ground = make_simple_material("MAT_PREVIEW_Ground", "2B2C2D", 0.83)
assign_material(body, mat_skin)
for eye in [obj for obj in human_collection.objects if ".eye." in obj.name or obj.name.endswith("eye.L") or obj.name.endswith("eye.R")]:
    assign_material(eye, mat_eye)
    set_smooth(eye)

# Add explicit iris, pupil and corneal highlights at the exact appended eye centers.
bpy.context.view_layer.update()
base_eyes = [obj for obj in human_collection.objects if ".eye." in obj.name or obj.name.endswith("eye.L") or obj.name.endswith("eye.R")]
eye_centers = sorted([obj.matrix_world.translation.copy() for obj in base_eyes], key=lambda point: point.x)
if len(eye_centers) != 2:
    eye_centers = [Vector((-0.0355, -0.131, 1.695)), Vector((0.0355, -0.131, 1.695))]
for index, center in enumerate(eye_centers):
    side = "L" if center.x < 0.0 else "R"
    make_uv_sphere("EyeIris_" + side, center + Vector((0.0, -0.0138, 0.0)), (0.0063, 0.0011, 0.0063), mat_iris, "Body", head_pivot, 36, 18)
    make_uv_sphere("EyePupil_" + side, center + Vector((0.0, -0.0146, 0.0)), (0.0025, 0.0007, 0.0025), mat_pupil, "Body", head_pivot, 28, 14)
    make_uv_sphere("EyeCornea_" + side, center + Vector((0.0, -0.0004, 0.0)), (0.0131, 0.0131, 0.0131), mat_cornea, "Body", head_pivot, 48, 24)
eye_level = sum(point.z for point in eye_centers) / len(eye_centers)

# Body-conforming underlayers preserve the scanned hands, face, and anatomical silhouette.
gambeson = subset_shell(
    "Cloth_Gambeson_BodyConforming",
    body,
    lambda co: (
        (0.66 < co.z < 1.435 and abs(co.x) < 0.205) or
        (0.91 < co.z < 1.445 and abs(co.x) >= 0.175)
    ),
    0.012,
    mat_linen,
    solidify=0.0065,
    subdivision=1,
)
parent_keep_world(gambeson, visual_root)
trousers = subset_shell(
    "Cloth_Trousers_BodyConforming",
    body,
    lambda co: 0.095 < co.z < 0.925 and abs(co.x) < 0.22,
    0.009,
    mat_trousers,
    solidify=0.0045,
    subdivision=1,
)
parent_keep_world(trousers, visual_root)
upper_coat = subset_shell(
    "Cloth_OuterCoat_TailoredUpper",
    body,
    lambda co: (
        0.855 < co.z < 1.395 and
        abs(co.x) < (0.255 if co.z > 1.27 else 0.215) and
        not (co.y < -0.040 and abs(co.x) < (0.030 + max(0.0, co.z - 1.05) * 0.31))
    ),
    0.025,
    mat_dark_cloth,
    solidify=0.008,
    subdivision=1,
)
parent_keep_world(upper_coat, visual_root)

# Long wool panels with asymmetric folds, real thickness, front and rear splits.
make_draped_panel("Cloth_CoatTail_FrontL", "X", -0.245, -0.035, 0.99, 0.39, -0.170, -1.0, mat_dark_cloth, 0.2, parent=visual_root)
make_draped_panel("Cloth_CoatTail_FrontR", "X", 0.035, 0.245, 0.99, 0.41, -0.170, -1.0, mat_dark_cloth, 1.1, parent=visual_root)
make_draped_panel("Cloth_CoatTail_BackL", "X", -0.250, -0.025, 0.99, 0.38, 0.170, 1.0, mat_dark_cloth, 2.0, parent=visual_root)
make_draped_panel("Cloth_CoatTail_BackR", "X", 0.025, 0.250, 0.99, 0.40, 0.170, 1.0, mat_dark_cloth, 2.7, parent=visual_root)
make_draped_panel("Cloth_CoatTail_SideL", "Y", -0.145, 0.145, 0.98, 0.43, -0.246, -1.0, mat_dark_cloth, 0.6, parent=visual_root, u_segments=20)
make_draped_panel("Cloth_CoatTail_SideR", "Y", -0.145, 0.145, 0.98, 0.42, 0.246, 1.0, mat_dark_cloth, 1.7, parent=visual_root, u_segments=20)

# Quilted center tab visible through the split coat.
make_draped_panel("Cloth_Gambeson_CenterTab", "X", -0.115, 0.115, 1.02, 0.48, -0.183, -1.0, mat_linen, 0.8, parent=visual_root, u_segments=18, v_segments=32)

# Dense layered cowl with broad shoulder folds and a lowered hood drape.
make_elliptic_loft(
    "Cloth_Cowl_MainDrape",
    [
        (1.365, 0.250, 0.178),
        (1.392, 0.270, 0.188),
        (1.422, 0.252, 0.180),
        (1.448, 0.218, 0.158),
    ],
    mat_cowl,
    segments=72,
    folds=0.070,
    solidify=0.008,
    subdivision=1,
    parent=visual_root,
)
for fold_index, (z, radius, thickness, sx, sy) in enumerate((
    (1.432, 0.164, 0.019, 1.25, 1.00),
    (1.474, 0.128, 0.018, 1.30, 1.00),
    (1.514, 0.098, 0.016, 1.24, 1.00),
)):
    make_torus(
        f"Cloth_Cowl_CompressionFold_{fold_index + 1:02d}",
        (0.0, -0.010 * fold_index, z),
        radius,
        thickness,
        mat_cowl,
        scale=(sx, sy, 1.0),
        parent=visual_root,
    )

# Hair cap plus hundreds of individually modelled, tapered strands.
hair_center = Vector((0.0, -0.004, eye_level + 0.018))
hair_radii = Vector((0.108, 0.132, 0.118))
make_scalp_cap(hair_center, hair_radii, mat_hair_cap, head_pivot)
hair_strands = []
for _ in range(720):
    phi = RNG.uniform(0.0, math.tau)
    front = max(0.0, -math.sin(phi))
    theta_max = 1.50 - 0.15 * front
    theta = RNG.uniform(0.10, theta_max)
    normal = Vector((math.sin(theta) * math.cos(phi), math.sin(theta) * math.sin(phi), math.cos(theta)))
    root_point = hair_center + Vector((hair_radii.x * normal.x, hair_radii.y * normal.y, hair_radii.z * normal.z))
    side_drop = 0.018 + 0.048 * (theta / theta_max) ** 1.8
    if root_point.y > 0.030:
        side_drop += 0.022
    if root_point.y < -0.035 and root_point.z > eye_level + 0.065:
        side_drop += RNG.uniform(0.008, 0.026)
    gravity = Vector((0.0, 0.0, -1.0))
    tangent = gravity - normal * gravity.dot(normal)
    if tangent.length < 0.12:
        tangent = Vector((math.cos(phi), math.sin(phi), -0.18))
    tangent.normalize()
    if root_point.y < -0.035:
        tangent = (tangent + Vector((0.0, -0.30, -0.10))).normalized()
    jitter = Vector((RNG.uniform(-0.006, 0.006), RNG.uniform(-0.005, 0.005), RNG.uniform(-0.002, 0.002)))
    hair_strands.append([
        root_point,
        root_point + normal * 0.0015 + tangent * side_drop * 0.24 + jitter * 0.25,
        root_point + tangent * side_drop * 0.52 + jitter * 0.55,
        root_point + tangent * side_drop * 0.78 + jitter * 0.85 + Vector((0, 0, -0.004)),
        root_point + tangent * side_drop + jitter + Vector((0, RNG.uniform(-0.003, 0.003), -0.008)),
    ])
# Dense, irregular forelocks and temple locks break up the bare scalp silhouette.
for index in range(86):
    t = index / 85.0
    x = -0.078 + 0.156 * t + RNG.uniform(-0.004, 0.004)
    arch = 0.018 * max(0.0, 1.0 - (x / 0.080) ** 2)
    root_point = Vector((x, -0.124 + RNG.uniform(-0.006, 0.006), eye_level + 0.072 + arch + RNG.uniform(-0.006, 0.006)))
    tip = Vector((x + RNG.uniform(-0.016, 0.016), -0.151, eye_level + RNG.uniform(0.010, 0.067)))
    hair_strands.append([
        root_point,
        root_point.lerp(tip, 0.30) + Vector((RNG.uniform(-0.004, 0.004), -0.004, 0.008)),
        root_point.lerp(tip, 0.65) + Vector((RNG.uniform(-0.005, 0.005), -0.003, 0.003)),
        tip,
    ])
for side in (-1.0, 1.0):
    for _ in range(85):
        root_point = Vector((side * RNG.uniform(0.072, 0.097), RNG.uniform(-0.035, 0.040), RNG.uniform(eye_level + 0.045, eye_level + 0.105)))
        tip = Vector((side * RNG.uniform(0.094, 0.108), RNG.uniform(-0.070, 0.025), RNG.uniform(eye_level - 0.050, eye_level + 0.015)))
        hair_strands.append([root_point, root_point.lerp(tip, 0.34), root_point.lerp(tip, 0.70), tip])
make_poly_curve("Hair_Unkempt_Strands", hair_strands, mat_hair, 0.00115, "Hair", head_pivot, 2, True)

# Short beard, jaw stubble, moustache and eyebrows built from curve strands.
beard_strands = []
beard_center_z = eye_level - 0.079
for _ in range(620):
    x = RNG.uniform(-0.079, 0.079)
    z = RNG.uniform(beard_center_z - 0.055, beard_center_z + 0.040)
    ellipse = (x / 0.080) ** 2 + ((z - beard_center_z) / 0.060) ** 2
    if ellipse > 1.0 or (z > beard_center_z + 0.018 and abs(x) < 0.033):
        continue
    y = -0.131 - 0.008 * max(0.0, 1.0 - (x / 0.080) ** 2)
    root_point = Vector((x, y, z))
    length = RNG.uniform(0.006, 0.020) + 0.014 * max(0.0, 1.0 - abs(x) / 0.08) * max(0.0, (beard_center_z + 0.015 - z) / 0.07)
    drift = Vector((RNG.uniform(-0.004, 0.004), RNG.uniform(-0.003, 0.002), -length))
    beard_strands.append([root_point, root_point + drift * 0.32, root_point + drift * 0.68, root_point + drift])
for side in (-1.0, 1.0):
    for index in range(48):
        x = side * (0.006 + 0.038 * index / 47.0)
        root_point = Vector((x, -0.139, eye_level - 0.054 + 0.003 * math.sin(index * 0.25)))
        beard_strands.append([root_point, root_point + Vector((side * 0.005, -0.001, -0.004)), root_point + Vector((side * 0.011, 0.0, -0.008))])
make_poly_curve("Hair_Beard_Stubble", beard_strands, mat_hair, 0.00082, "Hair", head_pivot, 1, True)
for side, x0 in ((-1.0, -0.036), (1.0, 0.036)):
    brow_lines = []
    for lane in range(12):
        z = eye_level + 0.024 + lane * 0.00035
        brow_lines.append([
            Vector((x0 - side * 0.022, -0.137, z - 0.002)),
            Vector((x0, -0.141, z + 0.003)),
            Vector((x0 + side * 0.024, -0.137, z - 0.001)),
        ])
    make_poly_curve(f"Hair_Eyebrow_{'L' if side < 0 else 'R'}", brow_lines, mat_hair, 0.00055, "Hair", head_pivot, 1, True)

# Harness, double belts, buckles and pouches.
front_harness = (
    ((-0.205, -0.231, 1.390), (0.155, -0.198, 1.025)),
    ((0.205, -0.231, 1.390), (-0.155, -0.198, 1.025)),
)
back_harness = (
    ((-0.205, 0.231, 1.390), (0.155, 0.198, 1.025)),
    ((0.205, 0.231, 1.390), (-0.155, 0.198, 1.025)),
)
for index, (a, b) in enumerate(front_harness):
    make_box_between(f"Leather_Harness_Front_{index+1:02d}", a, b, 0.038, 0.012, mat_leather_light, 0.0045, "Leather", torso_pivot)
for index, (a, b) in enumerate(back_harness):
    make_box_between(f"Leather_Harness_Back_{index+1:02d}", a, b, 0.038, 0.012, mat_leather_light, 0.0045, "Leather", back_pivot)
make_box("Leather_Harness_Center", (0.0, -0.239, 1.207), (0.062, 0.014, 0.062), mat_leather, (0, 0, math.radians(45)), 0.006, "Leather", torso_pivot)
for x, z in ((-0.020, 1.207), (0.020, 1.207), (0, 1.228), (0, 1.186)):
    make_uv_sphere("Iron_Harness_Rivet", (x, -0.248, z), (0.0055, 0.003, 0.0055), mat_iron_worn, "Armor", torso_pivot, 20, 10)
make_elliptic_loft("Leather_Waist_Belt", [(0.970, 0.248, 0.158), (1.010, 0.248, 0.158)], mat_leather, 64, 0.0, False, False, 0.006, 0, "Leather", visual_root)
make_elliptic_loft("Leather_Equipment_Belt", [(0.910, 0.265, 0.168), (0.943, 0.265, 0.168)], mat_leather_light, 64, 0.0, False, False, 0.006, 0, "Leather", visual_root)
make_box("Iron_Waist_Buckle", (0.0, -0.174, 0.991), (0.058, 0.016, 0.046), mat_iron_worn, bevel=0.005, category="Armor", parent=visual_root)
for name, location, dims, angle in (
    ("Left", (-0.245, -0.060, 0.865), (0.125, 0.078, 0.155), 8.0),
    ("FrontLeft", (-0.170, -0.176, 0.870), (0.125, 0.070, 0.145), -4.0),
    ("FrontRight", (0.105, -0.178, 0.880), (0.100, 0.064, 0.125), 5.0),
):
    make_box(f"Leather_Pouch_{name}", location, dims, mat_leather, (math.radians(-3), 0, math.radians(angle)), 0.014, "Leather", visual_root)
    make_box(f"Leather_Pouch_{name}_Flap", (location[0], location[1] - dims[1] * 0.51, location[2] + dims[2] * 0.23), (dims[0] * 0.92, 0.014, dims[2] * 0.44), mat_leather_light, (math.radians(-9), 0, math.radians(angle)), 0.006, "Leather", visual_root)

# Bracers follow the new arms and overlap the padded sleeves without hiding the scanned hands.
for side, x in ((-1.0, -0.265), (1.0, 0.265)):
    centers = [(x, -0.005, 0.79), (x * 0.99, -0.001, 0.91), (x * 0.96, 0.000, 1.045)]
    make_profile_tube(
        f"Leather_Bracer_{'L' if side < 0 else 'R'}",
        centers,
        [(0.060, 0.050), (0.066, 0.054), (0.072, 0.058)],
        mat_leather,
        36,
        True,
        True,
        "Leather",
        visual_root,
    )
    for wrap in range(7):
        z = 0.805 + wrap * 0.038
        make_torus(
            f"Leather_BracerWrap_{'L' if side < 0 else 'R'}_{wrap+1:02d}",
            (x, -0.006, z),
            0.058 + wrap * 0.0015,
            0.0055,
            mat_leather_light,
            scale=(1.0, 0.82, 1.0),
            parent=visual_root,
            major_segments=40,
            minor_segments=10,
        )

# Boots, layered wraps and crossed lacing.
def make_shoe(name, x):
    sections = [
        (-0.245, 0.052, 0.085, 0.034),
        (-0.205, 0.090, 0.088, 0.055),
        (-0.125, 0.102, 0.094, 0.069),
        (-0.015, 0.098, 0.099, 0.077),
        (0.105, 0.084, 0.087, 0.063),
        (0.140, 0.060, 0.082, 0.045),
    ]
    points = [(x, y, z) for y, _rx, z, _rz in sections]
    radii = [(rz, rx) for _y, rx, _z, rz in sections]
    shoe = make_profile_tube(name, points, radii, mat_leather, 32, True, True, "Leather", visual_root)
    sub = shoe.modifiers.new("BootSubdivision", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    make_box(name + "_Sole", (x, -0.050, 0.028), (0.215, 0.345, 0.038), mat_leather, bevel=0.014, category="Leather", parent=visual_root)


for side, x in (("L", -0.195), ("R", 0.195)):
    make_shoe(f"Leather_Boot_{side}", x)
    make_elliptic_loft(
        f"Leather_BootShaft_{side}",
        [(0.105, 0.082, 0.068, x, 0.0), (0.190, 0.087, 0.071, x, 0.0), (0.340, 0.091, 0.074, x, 0.0), (0.490, 0.094, 0.077, x, 0.0)],
        mat_leather,
        48,
        0.030,
        True,
        True,
        0.0,
        1,
        "Leather",
        visual_root,
    )
    for lace_index, z in enumerate((0.18, 0.25, 0.32, 0.39, 0.46)):
        make_box_between(f"Leather_BootLace_{side}_{lace_index+1:02d}A", (x - 0.073, -0.079, z - 0.025), (x + 0.073, -0.081, z + 0.025), 0.007, 0.004, mat_leather_light, 0.0015, "Leather", visual_root)
        make_box_between(f"Leather_BootLace_{side}_{lace_index+1:02d}B", (x + 0.073, -0.079, z - 0.025), (x - 0.073, -0.081, z + 0.025), 0.007, 0.004, mat_leather_light, 0.0015, "Leather", visual_root)

# Diagonal leather quiver and seven readable crossbow bolts.
quiver_low = Vector((-0.225, 0.270, 0.79))
quiver_mid = Vector((-0.025, 0.280, 1.11))
quiver_high = Vector((0.175, 0.282, 1.43))
qdir = (quiver_high - quiver_low).normalized()
make_profile_tube("Quiver_Leather_Body", [quiver_low, quiver_mid, quiver_high], [(0.060, 0.050), (0.067, 0.055), (0.072, 0.060)], mat_leather, 40, True, False, "Leather", quiver_pivot)
make_cone_between("Quiver_Mouth_Rim", quiver_high - qdir * 0.018, quiver_high + qdir * 0.018, 0.078, 0.078, mat_leather_light, 40, "Leather", quiver_pivot, False)
make_cone_between("Quiver_Dark_Interior", quiver_high - qdir * 0.003, quiver_high + qdir * 0.002, 0.058, 0.058, mat_string, 40, "Leather", quiver_pivot, True)
bolt_offsets = ((-.030,-.018,0),(-.010,-.025,.025),(.010,-.020,-.005),(.031,-.014,.035),(-.024,.012,.015),(0,.016,.045),(.024,.012,.008))
for index, (ox, oy, extra) in enumerate(bolt_offsets):
    offset = Vector((ox, oy, 0.0))
    start = quiver_high - qdir * 0.035 + offset
    end = quiver_high + qdir * (0.210 + extra) + offset
    make_cone_between(f"Weapon_Bolt_Shaft_{index+1:02d}", start, end, 0.0036, 0.0028, mat_wood, 16, "Weapon", quiver_pivot)
    make_box_between(f"Weapon_Bolt_Fletching_{index+1:02d}", end - qdir * 0.050, end - qdir * 0.008, 0.020, 0.003, mat_feather, 0.001, "Weapon", quiver_pivot)

# Sheathed dagger on the opposite hip.
dagger_top = Vector((0.302, -0.010, 0.905))
dagger_tip = Vector((0.355, 0.000, 0.535))
make_profile_tube("Dagger_Scabbard", [dagger_top, Vector((0.330, -0.006, 0.720)), dagger_tip], [(0.030, 0.020), (0.027, 0.018), (0.014, 0.012)], mat_leather, 28, True, True, "Weapon", dagger_pivot)
make_box("Dagger_Guard", (0.300, -0.012, 0.914), (0.125, 0.023, 0.020), mat_iron_worn, (0, math.radians(6), 0), 0.005, "Weapon", dagger_pivot)
make_cone_between("Dagger_Grip", (0.299, -0.012, 0.918), (0.282, -0.015, 1.035), 0.020, 0.017, mat_leather_light, 24, "Weapon", dagger_pivot)
make_uv_sphere("Dagger_Pommel", (0.279, -0.015, 1.052), (0.024, 0.018, 0.028), mat_iron_worn, "Weapon", dagger_pivot, 28, 14)

# Crossbow held vertically: sculpted wooden stock, metal prod, string, rail and stirrup.
stock_points = [
    (-0.370, -0.135, 0.155),
    (-0.372, -0.135, 0.330),
    (-0.360, -0.135, 0.560),
    (-0.350, -0.135, 0.790),
    (-0.355, -0.135, 0.985),
]
make_profile_tube("Crossbow_Wood_Stock", stock_points, [(0.033,0.027),(0.044,0.033),(0.060,0.038),(0.042,0.030),(0.026,0.022)], mat_wood, 40, True, True, "Weapon", crossbow_pivot)
make_box_between("Crossbow_Top_Rail", (-0.355, -0.165, 0.305), (-0.355, -0.165, 0.975), 0.026, 0.022, mat_iron, 0.004, "Weapon", crossbow_pivot)
make_box("Crossbow_Lock_Plate", (-0.355, -0.166, 0.790), (0.095, 0.020, 0.115), mat_iron, bevel=0.006, category="Weapon", parent=crossbow_pivot)
make_box_between("Crossbow_Grip", (-0.350, -0.125, 0.815), (-0.315, -0.110, 0.700), 0.055, 0.035, mat_wood, 0.008, "Weapon", crossbow_pivot)
bow_points = []
for index in range(21):
    t = index / 20.0
    x = -0.640 + 0.570 * t
    center_dist = abs(t - 0.5) * 2.0
    z = 0.335 - 0.060 * center_dist ** 1.7
    bow_points.append(Vector((x, -0.145, z)))
make_poly_curve("Crossbow_Steel_Prod", [bow_points], mat_iron_worn, 0.0085, "Weapon", crossbow_pivot, 3, True)
string_lines = [
    [bow_points[0], Vector((-0.355, -0.160, 0.405))],
    [bow_points[-1], Vector((-0.355, -0.160, 0.405))],
]
make_poly_curve("Crossbow_String", string_lines, mat_string, 0.00115, "Weapon", crossbow_pivot, 1, True)
make_poly_curve("Crossbow_Stirrup", [[Vector((-0.405,-0.140,0.175)),Vector((-0.425,-0.140,0.085)),Vector((-0.355,-0.140,0.045)),Vector((-0.285,-0.140,0.085)),Vector((-0.305,-0.140,0.175))]], mat_iron_worn, 0.006, "Weapon", crossbow_pivot, 2, True)
for wrap in range(5):
    make_torus(f"Crossbow_Prod_Binding_{wrap+1:02d}", (-0.355, -0.145, 0.330 + (wrap-2)*0.011), 0.032, 0.0035, mat_leather_light, scale=(1.0,0.75,1.0), parent=crossbow_pivot, major_segments=36, minor_segments=8, category="Weapon")

# Studio floor, lighting and Cycles render setup.
bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0.0, 0.0, -0.012))
ground = bpy.context.object
ground.name = "PREVIEW_Ground"
assign_material(ground, mat_ground)
move_to_collection(ground, preview_collection)

def add_area_light(name, location, energy, color, size, target=(0.0, 0.0, 1.0)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    preview_collection.objects.link(obj)
    obj.location = location
    look_at(obj, target)
    return obj


add_area_light("Key_Warm_Large", (-2.6, -3.3, 3.7), 420, (1.0, 0.73, 0.52), 2.1, (0,0,1.15))
add_area_light("Fill_Cool_Soft", (2.7, -2.0, 2.6), 150, (0.55, 0.68, 1.0), 2.6, (0,0,1.05))
add_area_light("Rim_Back", (0.6, 2.7, 3.4), 390, (1.0, 0.83, 0.65), 1.6, (0,0,1.25))
add_area_light("Face_EyeLight", (-0.5, -1.4, 2.25), 75, (1.0, 0.88, 0.73), 0.7, (0,0,1.66))

camera_data = bpy.data.cameras.new("PreviewCamera")
camera = bpy.data.objects.new("PreviewCamera", camera_data)
preview_collection.objects.link(camera)
scene.camera = camera
camera.data.lens = 72
camera.data.sensor_width = 36
camera.data.dof.use_dof = True
camera.data.dof.focus_object = head_pivot
camera.data.dof.aperture_fstop = 7.1

scene.render.engine = "BLENDER_EEVEE"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type in {"METAL", "CPU"}
    scene.render.engine = "CYCLES"
    scene.cycles.device = "GPU"
    scene.cycles.samples = 96
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.02
    scene.cycles.use_denoising = True
except Exception as error:
    print("Cycles Metal setup fallback:", error)
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.resolution_percentage = 100
scene.render.resolution_x = 720
scene.render.resolution_y = 920
scene.world.color = (0.018, 0.020, 0.023)
world_nodes = scene.world.node_tree.nodes if scene.world and scene.world.use_nodes else None
if scene.world:
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = color_from_hex("3B3E40")
    background.inputs["Strength"].default_value = 0.35
try:
    scene.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    pass


def render_preview(name, location, target, lens=72, resolution=(720, 920), samples=96):
    camera.location = location
    camera.data.lens = lens
    look_at(camera, target)
    scene.render.resolution_x = resolution[0]
    scene.render.resolution_y = resolution[1]
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = samples
    output = os.path.join(PREVIEW_DIR, name + ".png")
    scene.render.filepath = output
    bpy.ops.render.render(write_still=True)
    print("Rendered", output)


render_preview("mercenary_crossbowman_photoreal_three_quarter", (2.75, -3.55, 1.32), (0.0, 0.0, 0.98), 76, (760, 920), 96)
render_preview("mercenary_crossbowman_photoreal_front", (0.0, -4.15, 1.22), (0.0, 0.0, 0.96), 78, (720, 920), 80)
render_preview("mercenary_crossbowman_photoreal_side", (4.05, -0.05, 1.24), (0.0, 0.0, 0.98), 78, (720, 920), 72)
render_preview("mercenary_crossbowman_photoreal_back", (0.0, 4.10, 1.22), (0.0, 0.0, 0.98), 78, (720, 920), 72)
camera.data.dof.aperture_fstop = 5.6
render_preview("mercenary_crossbowman_photoreal_portrait", (0.72, -1.78, 1.77), (0.0, -0.01, 1.665), 92, (900, 900), 128)
camera.data.dof.aperture_fstop = 7.1

# Save the high-resolution authoring scene with packed CC0 PBR maps.
for obj in asset_collection.all_objects:
    obj.hide_render = False
for obj in preview_collection.all_objects:
    obj.hide_render = False
try:
    bpy.ops.file.pack_all()
except Exception as error:
    print("Texture packing warning:", error)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

# Export the complete model hierarchy. The multires viewport level is the game LOD0.
bpy.ops.object.select_all(action="DESELECT")
for obj in asset_collection.all_objects:
    obj.select_set(True)
gltf_properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
gltf_args = {
    "filepath": GLB_PATH,
    "export_format": "GLB",
    "use_selection": True,
    "export_apply": True,
    "export_yup": True,
    "export_cameras": False,
    "export_lights": False,
    "export_extras": True,
    "export_materials": "EXPORT",
    "export_image_format": "AUTO",
}
gltf_args = {key: value for key, value in gltf_args.items() if key in gltf_properties}
bpy.ops.export_scene.gltf(**gltf_args)
print("Saved photoreal authoring file:", BLEND_PATH)
print("Exported game GLB:", GLB_PATH)
print("Asset mesh count:", sum(1 for obj in asset_collection.all_objects if obj.type == "MESH"))
print("Asset material count:", len({slot.material.name for obj in asset_collection.all_objects if hasattr(obj.data, "materials") for slot in obj.material_slots if slot.material}))
