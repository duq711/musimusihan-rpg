import bpy
import math
import os
import random
from mathutils import Matrix, Vector


WORKSPACE = os.getcwd()
STAGING_DIR = os.path.join(WORKSPACE, "asset-staging", "blender_mercenary_crossbowman_game_ready")
TEXTURE_DIR = os.path.join(STAGING_DIR, "textures")
PREVIEW_DIR = os.path.join(STAGING_DIR, "previews")
BASE_BLEND = os.path.join(
    WORKSPACE,
    "asset-staging/blender_mercenary_crossbowman_photoreal/resources",
    "human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend",
)
BLEND_PATH = os.path.join(STAGING_DIR, "mercenary_crossbowman_game_ready_3d.blend")
GLB_PATH = os.path.join(
    WORKSPACE,
    "godot-game/assets/3d/dark_fantasy/mercenary_crossbowman_game_ready_3d.glb",
)
BODY_SCALE = 1.05330
BODY_SOURCE_X = -2.264302
RNG = random.Random(20260901)

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
    socket = node.inputs.get(name) if node else None
    if socket is not None:
        socket.default_value = value


def set_smooth(obj):
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True


def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def tag(obj, category):
    obj["part_category"] = category
    obj["game_asset"] = True


def move_to_collection(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)


def parent_keep_world(obj, parent):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world


def make_empty(name, location=(0.0, 0.0, 0.0), parent=None, size=0.05):
    obj = bpy.data.objects.new(name, None)
    asset_collection.objects.link(obj)
    obj.location = location
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = size
    if parent:
        obj.parent = parent
    return obj


def load_image(filename, non_color=False):
    image = bpy.data.images.load(os.path.join(TEXTURE_DIR, filename), check_existing=True)
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    return image


def make_pbr_material(name, prefix, tint=(1.0, 1.0, 1.0, 1.0), normal_strength=0.65, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    for node in list(nodes):
        nodes.remove(node)
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    base = nodes.new("ShaderNodeTexImage")
    normal = nodes.new("ShaderNodeTexImage")
    orm = nodes.new("ShaderNodeTexImage")
    separate = nodes.new("ShaderNodeSeparateColor")
    normal_map = nodes.new("ShaderNodeNormalMap")
    base.image = load_image(prefix + "_basecolor_4k.jpg")
    normal.image = load_image(prefix + "_normal_4k.png", True)
    orm.image = load_image(prefix + "_orm_4k.jpg", True)
    base.name = "BaseColor_4K"
    normal.name = "Normal_4K"
    orm.name = "ORM_4K"
    normal_map.inputs["Strength"].default_value = normal_strength
    set_input(bsdf, "Metallic", metallic)
    set_input(bsdf, "IOR", 1.45)
    links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(orm.outputs["Color"], separate.inputs["Color"])
    links.new(separate.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    material.diffuse_color = tint
    material["texture_set_resolution"] = 4096
    material["texture_set_prefix"] = prefix
    return material


def make_simple_material(name, color_hex, roughness=0.5, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    rgba = color_from_hex(color_hex)
    material.diffuse_color = rgba
    set_input(bsdf, "Base Color", rgba)
    set_input(bsdf, "Roughness", roughness)
    set_input(bsdf, "Metallic", metallic)
    return material


def make_hair_material():
    material = bpy.data.materials.new("MAT_HairCards_DarkBrown")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    for node in list(nodes):
        nodes.remove(node)
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = load_image("hair_cards_2k.png")
    tex.interpolation = "Linear"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    set_input(bsdf, "Roughness", 0.62)
    set_input(bsdf, "IOR", 1.55)
    material.diffuse_color = color_from_hex("1B100A")
    material.use_transparency_overlap = False
    try:
        material.surface_render_method = "DITHERED"
    except Exception:
        pass
    material["texture_set_resolution"] = 2048
    return material


def make_box(name, location, dimensions, material, rotation=(0.0, 0.0, 0.0), bevel=0.004, category="Leather"):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    move_to_collection(obj, asset_collection)
    if bevel:
        mod = obj.modifiers.new("EdgeWearBevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    assign_material(obj, material)
    set_smooth(obj)
    tag(obj, category)
    return obj


def make_box_between(name, a, b, width, thickness, material, bevel=0.003, category="Leather"):
    a = Vector(a)
    b = Vector(b)
    midpoint = (a + b) * 0.5
    vector = b - a
    obj = make_box(name, midpoint, (width, thickness, vector.length), material, bevel=bevel, category=category)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = vector.to_track_quat("Z", "Y")
    return obj


def make_profile_tube(name, points, radii, material, segments=32, cap_start=True, cap_end=True, category="Leather"):
    points = [Vector(point) for point in points]
    vertices = []
    for index, (point, radius) in enumerate(zip(points, radii)):
        rx, ry = radius
        for segment in range(segments):
            angle = math.tau * segment / segments
            vertices.append((point.x + math.cos(angle) * rx, point.y + math.sin(angle) * ry, point.z))
    faces = []
    for ring in range(len(points) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring * segments + segment
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + segment
            faces.append((a, b, c, d))
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
    tag(obj, category)
    return obj


def make_subset_shell_uv(name, body_obj, keep_face, offset, material, solidify=0.0, subdivision=0, category="Cloth"):
    body_obj.data.update()
    source_uv = body_obj.data.uv_layers.active
    used = {}
    vertices = []
    faces = []
    face_uvs = []
    for polygon in body_obj.data.polygons:
        center = sum((body_obj.data.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
        if not keep_face(center):
            continue
        new_face = []
        loop_uvs = []
        for source_loop_index, source_vertex_index in zip(polygon.loop_indices, polygon.vertices):
            if source_vertex_index not in used:
                vertex = body_obj.data.vertices[source_vertex_index]
                used[source_vertex_index] = len(vertices)
                vertices.append(vertex.co + vertex.normal * offset)
            new_face.append(used[source_vertex_index])
            if source_uv:
                loop_uvs.append(tuple(source_uv.data[source_loop_index].uv))
            else:
                loop_uvs.append((0.0, 0.0))
        faces.append(tuple(new_face))
        face_uvs.append(loop_uvs)
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon, uvs in zip(mesh.polygons, face_uvs):
        for loop_index, uv in zip(polygon.loop_indices, uvs):
            uv_layer.data[loop_index].uv = uv
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    if subdivision:
        mod = obj.modifiers.new("GarmentSubdivision", "SUBSURF")
        mod.levels = subdivision
        mod.render_levels = subdivision
    if solidify:
        mod = obj.modifiers.new("GarmentThickness", "SOLIDIFY")
        mod.thickness = solidify
        mod.offset = 0.0
    tag(obj, category)
    return obj


def make_coat_skirt(name, material):
    segments = 80
    rings = 25
    vertices = []
    uvs = []
    for ring in range(rings):
        v = ring / (rings - 1)
        z = 0.995 + (0.385 - 0.995) * v
        hem_irregularity = v ** 7 * (0.020 * math.sin(ring * 2.73))
        z += hem_irregularity
        rx = 0.300 + 0.035 * v + 0.012 * math.sin(v * math.pi)
        ry = 0.218 + 0.025 * v
        for segment in range(segments):
            angle = math.tau * segment / segments
            vertical_fold = v * (0.018 * math.sin(angle * 7.0 + 0.2) + 0.010 * math.sin(angle * 13.0 - 0.7))
            hem = v ** 8 * (0.010 * math.sin(angle * 19.0) + 0.006 * math.sin(angle * 31.0))
            local_z = z + hem
            vertices.append(((rx + vertical_fold) * math.cos(angle), (ry + vertical_fold * 0.55) * math.sin(angle), local_z))
            uvs.append((segment / segments, 1.0 - v))
    faces = []
    face_uvs = []
    for ring in range(rings - 1):
        v_mid = (ring + 0.5) / (rings - 1)
        for segment in range(segments):
            nxt = (segment + 1) % segments
            angle = math.tau * (segment + 0.5) / segments
            front_center = abs(((angle + math.pi / 2 + math.pi) % math.tau) - math.pi) < 0.105
            back_center = abs(((angle - math.pi / 2 + math.pi) % math.tau) - math.pi) < 0.080
            if v_mid > 0.08 and front_center:
                continue
            if v_mid > 0.38 and back_center:
                continue
            a = ring * segments + segment
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + segment
            faces.append((a, b, c, d))
            face_uvs.append((uvs[a], uvs[b], uvs[c], uvs[d]))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon, loop_uvs in zip(mesh.polygons, face_uvs):
        for loop_index, uv in zip(polygon.loop_indices, loop_uvs):
            layer.data[loop_index].uv = uv
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    solid = obj.modifiers.new("CoatThickness", "SOLIDIFY")
    solid.thickness = 0.007
    solid.offset = 0.0
    tag(obj, "Cloth")
    return obj


def make_cowl(name, material):
    segments = 96
    vertices = []
    uvs = []
    faces = []
    face_uvs = []
    bands = (
        ((1.350, 0.220, 0.152), (1.378, 0.267, 0.202), (1.410, 0.252, 0.188), (1.435, 0.214, 0.160)),
        ((1.405, 0.185, 0.142), (1.430, 0.224, 0.168), (1.458, 0.205, 0.153), (1.480, 0.166, 0.128)),
        ((1.455, 0.140, 0.112), (1.480, 0.178, 0.137), (1.510, 0.161, 0.125), (1.535, 0.118, 0.099)),
    )
    for band_index, band in enumerate(bands):
        base_index = len(vertices)
        for ring_index, (z_base, rx, ry) in enumerate(band):
            v = ring_index / (len(band) - 1)
            for segment in range(segments):
                angle = math.tau * segment / segments
                front = max(0.0, -math.sin(angle))
                back = max(0.0, math.sin(angle))
                irregular = 1.0 + 0.026 * math.sin(angle * 5.0 + band_index * 0.7) + 0.014 * math.sin(angle * 11.0 - ring_index * 0.4)
                z = z_base - front * (0.018 + band_index * 0.003) + back * (0.010 + band_index * 0.004)
                x = math.cos(angle) * rx * irregular
                y = math.sin(angle) * ry * irregular + back * (0.010 + band_index * 0.004)
                vertices.append((x, y, z))
                uvs.append((segment / segments, (band_index + v) / len(bands)))
        for ring_index in range(len(band) - 1):
            for segment in range(segments):
                nxt = (segment + 1) % segments
                a = base_index + ring_index * segments + segment
                b = base_index + ring_index * segments + nxt
                c = base_index + (ring_index + 1) * segments + nxt
                d = base_index + (ring_index + 1) * segments + segment
                faces.append((a, b, c, d))
                face_uvs.append((uvs[a], uvs[b], uvs[c], uvs[d]))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon, loop_uvs in zip(mesh.polygons, face_uvs):
        for loop_index, uv in zip(polygon.loop_indices, loop_uvs):
            layer.data[loop_index].uv = uv
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    solid = obj.modifiers.new("CowlThickness", "SOLIDIFY")
    solid.thickness = 0.007
    solid.offset = 0.0
    sub = obj.modifiers.new("CowlSubdivision", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    tag(obj, "Cloth")
    return obj


def make_hair_cap(name, center, radii, material):
    segments = 64
    rings = 18
    vertices = []
    faces = []
    for ring in range(rings + 1):
        t = ring / rings
        for segment in range(segments):
            phi = math.tau * segment / segments
            front = max(0.0, -math.sin(phi))
            theta_max = 1.48 - front * 0.24 + 0.035 * math.sin(phi * 3.0 + 0.4)
            theta = 0.025 + t * theta_max
            vertices.append((
                center.x + radii.x * math.sin(theta) * math.cos(phi),
                center.y + radii.y * math.sin(theta) * math.sin(phi),
                center.z + radii.z * math.cos(theta),
            ))
    for ring in range(rings):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring * segments + segment
            b = (ring + 1) * segments + segment
            c = (ring + 1) * segments + nxt
            d = ring * segments + nxt
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    tag(obj, "Hair")
    return obj


def make_gambeson_sleeve(name, sign, material):
    rings = 13
    segments = 48
    vertices = []
    uvs = []
    shoulder_x = 0.145 * sign
    wrist_x = 0.690 * sign
    for ring in range(rings):
        t = ring / (rings - 1)
        x = shoulder_x + (wrist_x - shoulder_x) * t
        radius_y = 0.118 - 0.055 * t + 0.012 * math.sin(t * math.pi * 4.0)
        radius_z = 0.152 - 0.078 * t + 0.014 * math.sin(t * math.pi * 3.0 + 0.4)
        center_z = 1.405 - 0.012 * math.sin(t * math.pi)
        for segment in range(segments):
            angle = math.tau * segment / segments
            quilt_softness = 1.0 + 0.035 * math.sin(angle * 6.0 + t * 13.0)
            vertices.append((x, math.cos(angle) * radius_y * quilt_softness, center_z + math.sin(angle) * radius_z * quilt_softness))
            uvs.append((t, segment / segments))
    faces = []
    face_uvs = []
    for ring in range(rings - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring * segments + segment
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + segment
            faces.append((a, b, c, d))
            face_uvs.append((uvs[a], uvs[b], uvs[c], uvs[d]))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon, loop_uvs in zip(mesh.polygons, face_uvs):
        for loop_index, uv in zip(polygon.loop_indices, loop_uvs):
            layer.data[loop_index].uv = uv
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    sub = obj.modifiers.new("SleeveSubdivision", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    solid = obj.modifiers.new("SleeveThickness", "SOLIDIFY")
    solid.thickness = 0.006
    solid.offset = 0.0
    tag(obj, "Cloth")
    return obj


def make_vest_torso(name, material):
    segments = 72
    rings = 17
    vertices = []
    uvs = []
    for ring in range(rings):
        v = ring / (rings - 1)
        z = 0.885 + (1.405 - 0.885) * v
        shoulder_t = max(0.0, min(1.0, (v - 0.66) / 0.34))
        shoulder = shoulder_t * shoulder_t * (3.0 - 2.0 * shoulder_t)
        rx = 0.225 + shoulder * 0.045 + 0.008 * math.sin(v * math.pi)
        ry = 0.165 + shoulder * 0.030
        for segment in range(segments):
            angle = math.tau * segment / segments
            subtle = 1.0 + 0.018 * math.sin(angle * 5.0 + v * 8.0)
            vertices.append((math.cos(angle) * rx * subtle, math.sin(angle) * ry * subtle, z))
            uvs.append((segment / segments, v))
    faces = []
    face_uvs = []
    for ring in range(rings - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring * segments + segment
            b = ring * segments + nxt
            c = (ring + 1) * segments + nxt
            d = (ring + 1) * segments + segment
            faces.append((a, b, c, d))
            face_uvs.append((uvs[a], uvs[b], uvs[c], uvs[d]))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon, loop_uvs in zip(mesh.polygons, face_uvs):
        for loop_index, uv in zip(polygon.loop_indices, loop_uvs):
            layer.data[loop_index].uv = uv
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    set_smooth(obj)
    solid = obj.modifiers.new("VestThickness", "SOLIDIFY")
    solid.thickness = 0.008
    solid.offset = 0.0
    tag(obj, "Cloth")
    return obj


def make_loose_trouser_leg(name, x, material):
    obj = make_profile_tube(
        name,
        [(x, 0.0, 0.445), (x, 0.0, 0.610), (x, 0.0, 0.790), (x, 0.0, 0.965)],
        [(0.112, 0.098), (0.125, 0.110), (0.145, 0.122), (0.160, 0.135)],
        material,
        segments=44,
        category="Cloth",
    )
    sub = obj.modifiers.new("TrouserSoftSubdivision", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    return obj


def make_ribbon_cards(name, card_point_sets, widths, material, category="Hair"):
    vertices = []
    faces = []
    uvs = []
    for card_index, points in enumerate(card_point_sets):
        points = [Vector(point) for point in points]
        card_width = widths[card_index]
        start = len(vertices)
        for index, point in enumerate(points):
            if index == 0:
                tangent = (points[1] - points[0]).normalized()
            elif index == len(points) - 1:
                tangent = (points[-1] - points[-2]).normalized()
            else:
                tangent = (points[index + 1] - points[index - 1]).normalized()
            radial = Vector((point.x, point.y + 0.015, max(0.02, point.z - 1.62))).normalized()
            side = tangent.cross(radial)
            if side.length < 0.01:
                side = Vector((1.0, 0.0, 0.0))
            side.normalize()
            taper = max(0.10, 1.0 - index / (len(points) - 1) * 0.86)
            half = side * card_width * taper * 0.5
            vertices.extend((point - half, point + half))
            v = index / (len(points) - 1)
            uvs.extend(((0.0, v), (1.0, v)))
        for index in range(len(points) - 1):
            a = start + index * 2
            faces.append((a, a + 1, a + 3, a + 2))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index, vertex_index in zip(polygon.loop_indices, polygon.vertices):
            layer.data[loop_index].uv = uvs[vertex_index]
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    tag(obj, category)
    return obj


def make_curve_strands(name, polylines, material, bevel_depth, category="Hair"):
    curve = bpy.data.curves.new(name + "Curve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 0
    curve.resolution_u = 1
    curve.fill_mode = "FULL"
    curve.use_fill_caps = True
    for points in polylines:
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for index, point in enumerate(points):
            spline.points[index].co = (*point, 1.0)
            spline.points[index].radius = max(0.12, 1.0 - 0.82 * index / max(1, len(points) - 1))
    obj = bpy.data.objects.new(name, curve)
    asset_collection.objects.link(obj)
    assign_material(obj, material)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    set_smooth(obj)
    tag(obj, category)
    return obj


def count_triangles(objects):
    total = 0
    breakdown = {}
    for obj in objects:
        if obj.type != "MESH":
            continue
        triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        total += triangles
        category = obj.get("part_category", "Other")
        breakdown[category] = breakdown.get(category, 0) + triangles
    return total, breakdown


def ensure_uv(obj):
    if obj.type != "MESH" or obj.data.uv_layers:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015)
    bpy.ops.object.mode_set(mode="OBJECT")


def apply_all_modifiers(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        except RuntimeError:
            obj.modifiers.remove(modifier)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Scene and hierarchy.
scene = bpy.context.scene
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    bpy.data.collections.remove(collection)

asset_collection = bpy.data.collections.new("CHR_Mercenary_GameReady")
preview_collection = bpy.data.collections.new("PREVIEW_STUDIO")
scene.collection.children.link(asset_collection)
scene.collection.children.link(preview_collection)
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

character_root = make_empty("CHARACTER_ROOT", size=0.08)
character_root["asset_type"] = "character"
character_root["character_role"] = "medieval_mercenary_commoner"
character_root["variant"] = "game_ready_photoreal_v5"
character_root["height_m"] = 1.78
character_root["rest_pose"] = "T_POSE"
character_root["target_engine"] = "Godot"
character_root["target_lod0_triangles"] = "100000-150000"
character_root["reference_priority"] = "face,clothing,silhouette"
character_root["excluded_parts"] = "weapons,quiver,pouches,scabbards"
visual_root = make_empty("VisualRoot", parent=character_root, size=0.055)


# Materials use portable image textures so the Godot GLB receives the same maps.
mat_skin = make_pbr_material("MAT_Skin_Weathered_4K", "skin", normal_strength=0.72)
skin_bsdf = next((node for node in mat_skin.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
set_input(skin_bsdf, "Subsurface Weight", 0.055)
set_input(skin_bsdf, "Specular IOR Level", 0.28)
set_input(skin_bsdf, "Subsurface Scale", 0.010)
mat_gambeson = make_pbr_material("MAT_Gambeson_Quilted_4K", "gambeson", normal_strength=0.88)
mat_outer = make_pbr_material("MAT_OuterCoat_WornWool_4K", "outer_wool", normal_strength=0.72)
mat_cowl = make_pbr_material("MAT_Cowl_HeavyWool_4K", "cowl_wool", normal_strength=0.78)
mat_leather = make_pbr_material("MAT_Leather_Worn_4K", "leather", normal_strength=0.76)
mat_hair = make_hair_material()
mat_hair_opaque = make_simple_material("MAT_Hair_OpaqueDarkBrown", "090503", 0.78)
hair_bsdf = mat_hair_opaque.node_tree.nodes.get("Principled BSDF")
set_input(hair_bsdf, "Coat Weight", 0.10)
mat_hair_cap = mat_hair_opaque
mat_eye = make_simple_material("MAT_EyeSclera", "B8ACA0", 0.26)
mat_iris = make_simple_material("MAT_IrisHazel", "3B2818", 0.22)
mat_pupil = make_simple_material("MAT_Pupil", "020202", 0.16)
mat_cornea = make_simple_material("MAT_Cornea", "E8F0EE", 0.04)
cornea_bsdf = mat_cornea.node_tree.nodes.get("Principled BSDF")
set_input(cornea_bsdf, "Transmission Weight", 0.86)
set_input(cornea_bsdf, "Coat Weight", 0.62)
set_input(cornea_bsdf, "IOR", 1.376)


# Append the official CC0 retopologized male body.
with bpy.data.libraries.load(BASE_BLEND, link=False) as (data_from, data_to):
    if "Body Male - Realistic" not in data_from.collections:
        raise RuntimeError("Official Body Male - Realistic collection is missing")
    data_to.collections = ["Body Male - Realistic"]
human_collection = data_to.collections[0]
human_collection.name = "SOURCE_HumanBase_CC0"
scene.collection.children.link(human_collection)

body = next(
    (obj for obj in human_collection.objects if obj.name.startswith("GEO-body_male_realistic") and ".eye." not in obj.name),
    None,
)
if body is None:
    raise RuntimeError("Human base body was not found")
body.name = "Body_Skin_GameReady"
for modifier in list(body.modifiers):
    body.modifiers.remove(modifier)


# Convert the source relaxed pose to a true T-pose and push the face toward the reference.
for vertex in body.data.vertices:
    co = vertex.co.copy()
    side = 1.0 if co.x >= 0.0 else -1.0
    lateral = abs(co.x)
    arm_weight = max(0.0, min(1.0, (lateral - 0.155) / 0.125))
    arm_weight *= max(0.0, min(1.0, (1.49 - co.z) / 0.22))
    if arm_weight > 0.0 and 0.67 < co.z < 1.50 and (co.z > 1.08 or lateral > 0.25):
        pivot = Vector((0.170 * side, 0.0, 1.385))
        angle = math.radians(-64.0 * side * arm_weight)
        delta = co - pivot
        rotated = Vector((
            math.cos(angle) * delta.x + math.sin(angle) * delta.z,
            delta.y,
            -math.sin(angle) * delta.x + math.cos(angle) * delta.z,
        ))
        co = pivot + rotated

    # Reference face: broad U-shaped jaw, stronger cheekbones, long nose and tired eye area.
    if 1.455 < co.z < 1.535 and co.y < -0.018 and abs(co.x) < 0.100:
        weight = max(0.0, 1.0 - abs(co.z - 1.495) / 0.045)
        co.x *= 1.0 + 0.180 * weight
        co.y -= 0.0065 * weight
    if 1.535 < co.z < 1.600 and co.y < -0.048 and 0.035 < abs(co.x) < 0.090:
        cheek = max(0.0, 1.0 - abs(co.z - 1.568) / 0.034)
        co.x *= 1.0 + 0.055 * cheek
        co.y -= 0.0028 * cheek
    if 1.535 < co.z < 1.625 and co.y < -0.065 and abs(co.x) < 0.030:
        nose = max(0.0, 1.0 - abs(co.x) / 0.030)
        co.y -= 0.0065 * nose
    if 1.585 < co.z < 1.635 and co.y < -0.040 and 0.020 < abs(co.x) < 0.075:
        co.y -= 0.0025
    if 1.505 < co.z < 1.560 and co.y < -0.025 and 0.042 < abs(co.x) < 0.095:
        co.y += 0.0025
    if 1.430 < co.z < 1.500 and co.y < -0.030 and abs(co.x) < 0.065:
        chin = max(0.0, 1.0 - abs(co.z - 1.465) / 0.036)
        co.y -= 0.0060 * chin
    vertex.co = co
body.data.update()
set_smooth(body)


# Center and scale the appended hierarchy, then bake every source mesh to world space.
source_root = bpy.data.objects.new("SOURCE_HumanRoot", None)
scene.collection.objects.link(source_root)
for obj in list(human_collection.objects):
    if obj.parent is None:
        obj.parent = source_root
source_root.location = (-BODY_SOURCE_X * BODY_SCALE, 0.0, 0.006)
source_root.scale = (BODY_SCALE, BODY_SCALE, BODY_SCALE)
bpy.context.view_layer.update()

source_meshes = [obj for obj in human_collection.all_objects if obj.type == "MESH"]
world_matrices = {obj: obj.matrix_world.copy() for obj in source_meshes}
for obj in source_meshes:
    obj.data.transform(world_matrices[obj])
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    move_to_collection(obj, asset_collection)
bpy.data.objects.remove(source_root, do_unlink=True)
bpy.data.collections.remove(human_collection)

body = bpy.data.objects.get("Body_Skin_GameReady")
assign_material(body, mat_skin)
tag(body, "Body")
body["source"] = "Blender Human Base Meshes v1.4.1"
body["license"] = "CC0"

base_eyes = [obj for obj in source_meshes if obj != body]
for eye in base_eyes:
    eye.name = "EyeSclera_L" if eye.data.vertices[0].co.x < 0 else "EyeSclera_R"
    assign_material(eye, mat_eye)
    tag(eye, "Eyes")
    set_smooth(eye)


# Explicit iris, pupil and corneal shells retain readable eyes in Godot.
eye_centers = []
for eye in base_eyes:
    center = sum((vertex.co for vertex in eye.data.vertices), Vector()) / len(eye.data.vertices)
    eye_centers.append(center)
eye_centers.sort(key=lambda point: point.x)
for center in eye_centers:
    side_name = "L" if center.x < 0 else "R"
    for suffix, offset_y, scale, material in (
        ("Iris", -0.0128, (0.0065, 0.0010, 0.0065), mat_iris),
        ("Pupil", -0.0137, (0.0025, 0.0007, 0.0025), mat_pupil),
        ("Cornea", -0.0005, (0.0130, 0.0130, 0.0130), mat_cornea),
    ):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=center + Vector((0.0, offset_y, 0.0)))
        obj = bpy.context.object
        obj.name = f"Eye{suffix}_{side_name}"
        obj.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        move_to_collection(obj, asset_collection)
        assign_material(obj, material)
        set_smooth(obj)
        tag(obj, "Eyes")


# Body-conforming T-pose garment layers.
gambeson = make_subset_shell_uv(
    "Cloth_Gambeson_Quilted",
    body,
    lambda co: 0.625 < co.z < 1.435 and abs(co.x) < 0.245,
    0.0135,
    mat_gambeson,
    solidify=0.0075,
    subdivision=1,
)
gambeson_sleeve_l = make_gambeson_sleeve("Cloth_Gambeson_Sleeve_L", 1.0, mat_gambeson)
gambeson_sleeve_r = make_gambeson_sleeve("Cloth_Gambeson_Sleeve_R", -1.0, mat_gambeson)

trousers = make_subset_shell_uv(
    "Cloth_Trousers_Loose",
    body,
    lambda co: 0.090 < co.z < 0.955 and abs(co.x) < 0.245,
    0.018,
    mat_outer,
    solidify=0.0055,
    subdivision=0,
)
trouser_leg_l = make_loose_trouser_leg("Cloth_TrouserVolume_L", 0.105, mat_outer)
trouser_leg_r = make_loose_trouser_leg("Cloth_TrouserVolume_R", -0.105, mat_outer)

upper_coat = make_vest_torso("Cloth_OuterCoat_Upper", mat_outer)

coat_skirt = make_coat_skirt("Cloth_OuterCoat_LongSplitSkirt", mat_outer)
cowl = make_cowl("Cloth_Cowl_LayeredHeavyWool", mat_cowl)


# Quilted center tab visible through the open front coat.
tab_vertices = []
tab_faces = []
tab_uvs = []
u_segments = 18
v_segments = 28
for v_index in range(v_segments + 1):
    v = v_index / v_segments
    z = 1.005 + (0.465 - 1.005) * v
    for u_index in range(u_segments + 1):
        u = u_index / u_segments
        x = -0.112 + 0.224 * u
        y = -0.191 - 0.008 * math.sin(u * math.pi * 4.0) * v
        tab_vertices.append((x, y, z + 0.008 * v * math.sin(u * math.pi * 3.0)))
        tab_uvs.append((u, 1.0 - v))
stride = u_segments + 1
for v_index in range(v_segments):
    for u_index in range(u_segments):
        a = v_index * stride + u_index
        tab_faces.append((a, a + 1, a + 1 + stride, a + stride))
tab_mesh = bpy.data.meshes.new("Cloth_Gambeson_CenterTabMesh")
tab_mesh.from_pydata(tab_vertices, [], tab_faces)
tab_mesh.update()
tab_layer = tab_mesh.uv_layers.new(name="UVMap")
for polygon in tab_mesh.polygons:
    for loop_index, vertex_index in zip(polygon.loop_indices, polygon.vertices):
        tab_layer.data[loop_index].uv = tab_uvs[vertex_index]
center_tab = bpy.data.objects.new("Cloth_Gambeson_CenterTab", tab_mesh)
asset_collection.objects.link(center_tab)
assign_material(center_tab, mat_gambeson)
solid = center_tab.modifiers.new("TabThickness", "SOLIDIFY")
solid.thickness = 0.006
tag(center_tab, "Cloth")
chest_panel = make_box(
    "Cloth_Gambeson_ChestPanel",
    (0.0, -0.188, 1.205),
    (0.190, 0.012, 0.405),
    mat_gambeson,
    bevel=0.008,
    category="Cloth",
)


# Simplified identity-preserving harness and waist belt, with all bags and weapon mounts omitted.
for index, (a, b) in enumerate((
    ((-0.215, -0.238, 1.395), (0.155, -0.211, 1.025)),
    ((0.215, -0.238, 1.395), (-0.155, -0.211, 1.025)),
    ((-0.215, 0.232, 1.395), (0.155, 0.205, 1.025)),
    ((0.215, 0.232, 1.395), (-0.155, 0.205, 1.025)),
)):
    make_box_between(f"Leather_Harness_{index + 1:02d}", a, b, 0.038, 0.010, mat_leather, 0.0035)

make_profile_tube(
    "Leather_WaistBelt",
    [(0.0, 0.0, 0.965), (0.0, 0.0, 1.005)],
    [(0.267, 0.183), (0.267, 0.183)],
    mat_leather,
    segments=72,
    cap_start=False,
    cap_end=False,
)
make_box("Iron_BeltBuckle", (0.0, -0.191, 0.985), (0.062, 0.014, 0.050), mat_leather, bevel=0.004, category="Leather")


# Bracers stay clear of elbow and wrist deformation boundaries.
for side, x0 in (("L", -0.525), ("R", 0.525)):
    sign = -1.0 if x0 < 0 else 1.0
    make_profile_tube(
        f"Leather_ForearmBracer_{side}",
        [(x0 - sign * 0.080, 0.0, 1.380), (x0, 0.0, 1.380), (x0 + sign * 0.080, 0.0, 1.380)],
        [(0.054, 0.048), (0.062, 0.054), (0.068, 0.057)],
        mat_leather,
        segments=40,
    )
    for wrap in range(5):
        x = x0 - sign * 0.065 + sign * wrap * 0.032
        bpy.ops.mesh.primitive_torus_add(major_radius=0.058, minor_radius=0.0042, major_segments=36, minor_segments=8, location=(x, 0.0, 1.380), rotation=(0.0, math.radians(90.0), 0.0))
        ring = bpy.context.object
        ring.name = f"Leather_BracerWrap_{side}_{wrap + 1:02d}"
        ring.scale.y = 0.82
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        move_to_collection(ring, asset_collection)
        assign_material(ring, mat_leather)
        tag(ring, "Leather")


# Wrapped boots and sturdy soles.
for side, x in (("L", -0.105), ("R", 0.105)):
    make_profile_tube(
        f"Leather_BootFoot_{side}",
        [(x, -0.205, 0.072), (x, -0.135, 0.095), (x, -0.040, 0.105), (x, 0.070, 0.095)],
        [(0.080, 0.055), (0.098, 0.072), (0.105, 0.083), (0.082, 0.064)],
        mat_leather,
        segments=36,
    )
    make_box(f"Leather_BootSole_{side}", (x, -0.065, 0.028), (0.215, 0.350, 0.040), mat_leather, bevel=0.013)
    make_profile_tube(
        f"Leather_BootShaft_{side}",
        [(x, 0.0, 0.105), (x, 0.0, 0.205), (x, 0.0, 0.350), (x, 0.0, 0.505)],
        [(0.085, 0.067), (0.088, 0.070), (0.092, 0.074), (0.095, 0.078)],
        mat_leather,
        segments=44,
    )
    for lace_index, z in enumerate((0.18, 0.25, 0.32, 0.39, 0.46)):
        make_box_between(
            f"Leather_BootLace_{side}_{lace_index + 1:02d}A",
            (x - 0.072, -0.078, z - 0.026),
            (x + 0.072, -0.080, z + 0.026),
            0.007,
            0.0035,
            mat_leather,
            0.001,
        )
        make_box_between(
            f"Leather_BootLace_{side}_{lace_index + 1:02d}B",
            (x + 0.072, -0.078, z - 0.026),
            (x - 0.072, -0.080, z + 0.026),
            0.007,
            0.0035,
            mat_leather,
            0.001,
        )


# Layered hair cards: large clumps first, then sparse flyaways. Beard cards keep the face readable.
eye_level = sum(point.z for point in eye_centers) / max(1, len(eye_centers))
hair_center = Vector((0.0, -0.003, eye_level + 0.015))
hair_radii = Vector((0.101, 0.119, 0.108))
make_hair_cap("Hair_ScalpCap", hair_center, hair_radii, mat_hair_cap)

hair_cards = []
hair_widths = []
for _ in range(440):
    phi = RNG.uniform(0.0, math.tau)
    front = max(0.0, -math.sin(phi))
    theta = RNG.uniform(0.12, 1.42 - 0.13 * front)
    normal = Vector((math.sin(theta) * math.cos(phi), math.sin(theta) * math.sin(phi), math.cos(theta)))
    root = hair_center + Vector((hair_radii.x * normal.x, hair_radii.y * normal.y, hair_radii.z * normal.z))
    gravity = Vector((0.0, 0.0, -1.0))
    tangent = gravity - normal * gravity.dot(normal)
    if tangent.length < 0.08:
        tangent = Vector((math.cos(phi), math.sin(phi), -0.28))
    tangent.normalize()
    if root.y < -0.035:
        tangent = (tangent + Vector((0.0, -0.32, -0.08))).normalized()
    length = RNG.uniform(0.035, 0.085) + (0.022 if root.y > 0.025 else 0.0)
    jitter = Vector((RNG.uniform(-0.006, 0.006), RNG.uniform(-0.005, 0.005), RNG.uniform(-0.003, 0.003)))
    points = [
        root,
        root + tangent * length * 0.27 + normal * 0.002,
        root + tangent * length * 0.55 + jitter * 0.35,
        root + tangent * length * 0.80 + jitter * 0.70,
        root + tangent * length + jitter + Vector((0.0, 0.0, -0.006)),
    ]
    hair_cards.append(points)
    hair_widths.append(RNG.uniform(0.007, 0.014))

# Asymmetric fringe locks model the recognizable messy forehead silhouette.
for index in range(78):
    t = index / 77.0
    x = -0.085 + 0.170 * t + RNG.uniform(-0.004, 0.004)
    root = Vector((x, -0.129, eye_level + 0.082 + 0.020 * (1.0 - abs(t - 0.5) * 2.0)))
    tip = Vector((x + RNG.uniform(-0.018, 0.018), -0.153, eye_level + RNG.uniform(0.012, 0.065)))
    hair_cards.append([root, root.lerp(tip, 0.30) + Vector((0.0, -0.004, 0.008)), root.lerp(tip, 0.67), tip])
    hair_widths.append(RNG.uniform(0.006, 0.011))
hair = make_curve_strands("Hair_Unkempt_Strands", hair_cards, mat_hair_opaque, 0.00085)

beard_cards = []
beard_widths = []
beard_center_z = eye_level - 0.084
for _ in range(420):
    x = RNG.uniform(-0.082, 0.082)
    z = RNG.uniform(beard_center_z - 0.058, beard_center_z + 0.043)
    ellipse = (x / 0.084) ** 2 + ((z - beard_center_z) / 0.064) ** 2
    if ellipse > 1.0 or (z > beard_center_z + 0.020 and abs(x) < 0.032):
        continue
    y = -0.143 - 0.008 * max(0.0, 1.0 - abs(x) / 0.084)
    root = Vector((x, y, z))
    length = RNG.uniform(0.007, 0.020) + 0.009 * max(0.0, 1.0 - abs(x) / 0.084)
    tip = root + Vector((RNG.uniform(-0.005, 0.005), RNG.uniform(-0.003, 0.001), -length))
    beard_cards.append([root, root.lerp(tip, 0.45), tip])
    beard_widths.append(RNG.uniform(0.0045, 0.0080))
for side in (-1.0, 1.0):
    for index in range(58):
        t = index / 57.0
        x = side * (0.004 + 0.040 * t)
        root = Vector((x, -0.151, eye_level - 0.073 + 0.003 * math.sin(t * math.pi)))
        tip = root + Vector((side * (0.006 + 0.006 * t), -0.001, -0.004 - 0.004 * t))
        beard_cards.append([root, root.lerp(tip, 0.5), tip])
        beard_widths.append(0.0045)
beard = make_curve_strands("Hair_Beard_Strands", beard_cards, mat_hair_opaque, 0.00048)

brow_lines = []
for side in (-1.0, 1.0):
    for lane in range(18):
        z = eye_level + 0.026 + lane * 0.00028
        center_x = side * 0.038
        brow_lines.append([
            Vector((center_x - side * 0.025, -0.145, z - 0.003)),
            Vector((center_x, -0.149, z + 0.004)),
            Vector((center_x + side * 0.026, -0.144, z - 0.001)),
        ])
eyebrows = make_curve_strands("Hair_Eyebrow_Strands", brow_lines, mat_hair_opaque, 0.00042)


# Apply geometry modifiers before budget enforcement and skinning.
character_meshes = [obj for obj in asset_collection.objects if obj.type == "MESH" and obj.get("game_asset")]
for obj in character_meshes:
    parent_keep_world(obj, None) if obj.parent else None
    apply_all_modifiers(obj)
    ensure_uv(obj)
    triangulate = obj.modifiers.new("ExportTriangulation", "TRIANGULATE")
    triangulate.keep_custom_normals = True
    apply_all_modifiers(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    set_smooth(obj)


# Keep LOD0 in the requested range, preserving body/face topology and reducing garments only if needed.
triangle_total, triangle_breakdown = count_triangles(character_meshes)
print("TRIANGLES_PRE_BUDGET", triangle_total, triangle_breakdown)
if triangle_total > 148000:
    fixed = sum(
        sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        for obj in character_meshes
        if obj.get("part_category") in {"Body", "Eyes"}
    )
    variable = max(1, triangle_total - fixed)
    ratio = max(0.35, min(1.0, (144000 - fixed) / variable))
    for obj in character_meshes:
        if obj.get("part_category") in {"Body", "Eyes"} or len(obj.data.polygons) < 80:
            continue
        mod = obj.modifiers.new("LODBudgetDecimate", "DECIMATE")
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        apply_all_modifiers(obj)
elif triangle_total < 100000:
    for obj in (gambeson, upper_coat, coat_skirt, cowl):
        if obj and obj.name in bpy.data.objects:
            mod = obj.modifiers.new("LODDetailSubdivision", "SUBSURF")
            mod.levels = 1
            mod.render_levels = 1
            apply_all_modifiers(obj)
            triangle_total, _ = count_triangles(character_meshes)
            if triangle_total >= 112000:
                break

triangle_total, triangle_breakdown = count_triangles(character_meshes)
print("TRIANGLES_FINAL", triangle_total, triangle_breakdown)
character_root["lod0_triangles"] = triangle_total


# Rigify human metarig aligned to the 1.78m T-pose body.
bpy.ops.preferences.addon_enable(module="rigify")
bpy.ops.object.select_all(action="DESELECT")
bpy.ops.object.armature_human_metarig_add()
metarig = bpy.context.active_object
metarig.name = "metarig_mercenary"
metarig.data.name = "metarig_mercenary"
metarig.scale = (1.78 / 1.9796,) * 3
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
metarig.data.rigify_rig_basename = "mercenary_rig"

# Rotate and stretch each complete arm/finger hierarchy into a horizontal rest pose.
bpy.context.view_layer.objects.active = metarig
bpy.ops.object.mode_set(mode="EDIT")
body_extent_x = max(abs(vertex.co.x) for vertex in body.data.vertices)
for suffix, sign in ((".L", 1.0), (".R", -1.0)):
    upper = metarig.data.edit_bones.get("upper_arm" + suffix)
    if upper is None:
        continue
    descendants = []
    stack = [upper]
    while stack:
        bone = stack.pop()
        descendants.append(bone)
        stack.extend(list(bone.children))
    pivot = upper.head.copy()
    wrist = metarig.data.edit_bones.get("hand" + suffix)
    reference = wrist.tail if wrist else upper.tail
    u = sign * (reference.x - pivot.x)
    theta = math.atan2(reference.z - pivot.z, max(1e-6, u))

    def rotate_arm_point(point):
        delta = point - pivot
        local_u = sign * delta.x
        new_u = math.cos(theta) * local_u + math.sin(theta) * delta.z
        new_z = -math.sin(theta) * local_u + math.cos(theta) * delta.z
        return pivot + Vector((sign * new_u, delta.y, new_z))

    for bone in descendants:
        bone.head = rotate_arm_point(bone.head)
        bone.tail = rotate_arm_point(bone.tail)

    current_extent = max(sign * (point.x - pivot.x) for bone in descendants for point in (bone.head, bone.tail))
    target_extent = max(0.40, body_extent_x * 0.965 - sign * pivot.x)
    stretch = target_extent / max(current_extent, 1e-5)
    for bone in descendants:
        for attr in ("head", "tail"):
            point = getattr(bone, attr).copy()
            delta = point - pivot
            point.x = pivot.x + delta.x * stretch
            point.z = pivot.z + delta.z
            setattr(bone, attr, point)
bpy.ops.object.mode_set(mode="OBJECT")

bpy.context.view_layer.objects.active = metarig
metarig.select_set(True)
bpy.ops.pose.rigify_generate()
rig = next(
    obj for obj in scene.objects
    if obj.type == "ARMATURE" and obj != metarig and obj.name.startswith("mercenary_rig")
)
rig.name = "Mercenary_Rigify_Rig"
rig.data.name = "Mercenary_Rigify_Skeleton"
rig["rig_system"] = "Rigify"
rig["rest_pose"] = "T_POSE"
rig["export_deform_bones_only"] = True
move_to_collection(rig, asset_collection)
metarig.hide_viewport = True
metarig.hide_render = True


def normalized_blend(value, low, high):
    if high <= low:
        return 0.0
    t = max(0.0, min(1.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}


def add_weight(groups, name, weight):
    if weight > 1e-5 and name in deform_names:
        groups[name] = groups.get(name, 0.0) + weight


def weights_for_coordinate(co, category):
    x, y, z = co
    groups = {}
    # Rigify uses positive X for .L and negative X for .R.
    side = "L" if x >= 0.0 else "R"
    ax = abs(x)

    if category in {"Hair"}:
        return {"DEF-spine.006": 1.0}
    if category in {"Eyes"}:
        return {"DEF-spine.006": 1.0}

    if ax > 0.205 and z > 1.205:
        if ax < 0.345:
            t = normalized_blend(ax, 0.205, 0.345)
            add_weight(groups, "DEF-spine.004", 1.0 - t)
            add_weight(groups, "DEF-upper_arm." + side, t)
        elif ax < 0.485:
            t = normalized_blend(ax, 0.345, 0.485)
            add_weight(groups, "DEF-upper_arm." + side, 1.0 - t * 0.65)
            add_weight(groups, "DEF-upper_arm." + side + ".001", t * 0.65)
        elif ax < 0.650:
            t = normalized_blend(ax, 0.485, 0.650)
            add_weight(groups, "DEF-upper_arm." + side + ".001", 1.0 - t)
            add_weight(groups, "DEF-forearm." + side, t)
        elif ax < 0.770:
            t = normalized_blend(ax, 0.650, 0.770)
            add_weight(groups, "DEF-forearm." + side, 1.0 - t * 0.70)
            add_weight(groups, "DEF-forearm." + side + ".001", t * 0.70)
        else:
            t = normalized_blend(ax, 0.770, 0.835)
            add_weight(groups, "DEF-forearm." + side + ".001", 1.0 - t)
            add_weight(groups, "DEF-hand." + side, t)
    elif z < 1.015 and ax > 0.035:
        if z < 0.115:
            add_weight(groups, "DEF-foot." + side, 1.0)
        elif z < 0.540:
            t = normalized_blend(z, 0.115, 0.190)
            add_weight(groups, "DEF-foot." + side, 1.0 - t)
            add_weight(groups, "DEF-shin." + side, t)
        elif z < 0.620:
            t = normalized_blend(z, 0.540, 0.620)
            add_weight(groups, "DEF-shin." + side + ".001", 1.0 - t)
            add_weight(groups, "DEF-thigh." + side, t)
        else:
            t = normalized_blend(z, 0.620, 0.980)
            add_weight(groups, "DEF-thigh." + side, 0.75)
            add_weight(groups, "DEF-thigh." + side + ".001", 0.25 + t * 0.10)
    else:
        if z < 1.045:
            add_weight(groups, "DEF-spine", 0.65)
            add_weight(groups, "DEF-pelvis." + side, 0.35)
        elif z < 1.190:
            t = normalized_blend(z, 1.045, 1.190)
            add_weight(groups, "DEF-spine.001", 1.0 - t)
            add_weight(groups, "DEF-spine.002", t)
        elif z < 1.350:
            t = normalized_blend(z, 1.190, 1.350)
            add_weight(groups, "DEF-spine.003", 1.0 - t)
            add_weight(groups, "DEF-spine.004", t)
        elif z < 1.510:
            t = normalized_blend(z, 1.350, 1.510)
            add_weight(groups, "DEF-spine.004", 1.0 - t)
            add_weight(groups, "DEF-spine.005", t)
        else:
            add_weight(groups, "DEF-spine.006", 1.0)

    total = sum(groups.values())
    if total <= 1e-6:
        return {"DEF-spine": 1.0}
    return {name: weight / total for name, weight in groups.items()}


# Bind every render mesh to Rigify deform bones with deterministic, normalized weights.
for obj in character_meshes:
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    group_cache = {}
    category = obj.get("part_category", "Cloth")
    for vertex in obj.data.vertices:
        coordinate = obj.matrix_world @ vertex.co
        for bone_name, weight in weights_for_coordinate(coordinate, category).items():
            group = group_cache.get(bone_name)
            if group is None:
                group = obj.vertex_groups.new(name=bone_name)
                group_cache[bone_name] = group
            group.add([vertex.index], weight, "REPLACE")
    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


# Hide generated controls from renders; they remain in the .blend for animation.
for collection in bpy.data.collections:
    if collection.name.startswith("WGTS") or collection.name.startswith("WGT"):
        collection.hide_render = True
        collection.hide_viewport = True
for obj in scene.objects:
    if obj.name.startswith("WGT-"):
        obj.hide_render = True
        obj.hide_viewport = True


# Parent the generated animation rig below the stable game root.
parent_keep_world(rig, character_root)


# Neutral studio for T-pose review renders.
scene.world.color = color_from_hex("171717")[:3]
bpy.ops.mesh.primitive_plane_add(size=10.0, location=(0.0, 0.0, -0.012))
ground = bpy.context.object
ground.name = "PREVIEW_Ground"
move_to_collection(ground, preview_collection)
ground_mat = make_simple_material("MAT_PREVIEW_Ground", "252525", 0.82)
assign_material(ground, ground_mat)


def add_area_light(name, location, energy, color, size, target=(0.0, 0.0, 1.05)):
    data = bpy.data.lights.new(name + "Data", "AREA")
    data.energy = energy
    data.color = color
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    preview_collection.objects.link(obj)
    obj.location = location
    look_at(obj, target)
    return obj


add_area_light("PREVIEW_Key", (3.2, -4.0, 3.6), 680.0, (1.0, 0.86, 0.74), 3.0)
add_area_light("PREVIEW_Fill", (-3.5, -2.0, 2.2), 430.0, (0.62, 0.72, 1.0), 3.5)
add_area_light("PREVIEW_Rim", (1.0, 3.4, 3.4), 620.0, (1.0, 0.66, 0.48), 2.4, (0.0, 0.0, 1.35))
add_area_light("PREVIEW_Top", (0.0, 0.0, 5.0), 340.0, (1.0, 0.94, 0.86), 2.5)

camera_data = bpy.data.cameras.new("PREVIEW_CameraData")
camera = bpy.data.objects.new("PREVIEW_Camera", camera_data)
preview_collection.objects.link(camera)
scene.camera = camera

try:
    scene.render.engine = "BLENDER_EEVEE_NEXT"
except Exception:
    scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.resolution_percentage = 100
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.render.image_settings.compression = 25
scene.view_settings.look = "AgX - Medium High Contrast"


def render_orthographic(name, location, target, ortho_scale, resolution=(1200, 900)):
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x = resolution[0]
    scene.render.resolution_y = resolution[1]
    scene.render.filepath = os.path.join(PREVIEW_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)


def render_perspective(name, location, target, lens, resolution=(900, 900)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x = resolution[0]
    scene.render.resolution_y = resolution[1]
    scene.render.filepath = os.path.join(PREVIEW_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)


render_orthographic("mercenary_game_ready_tpose_front", (0.0, -5.5, 0.90), (0.0, 0.0, 0.90), 2.24)
render_orthographic("mercenary_game_ready_tpose_back", (0.0, 5.5, 0.90), (0.0, 0.0, 0.90), 2.24)
render_perspective("mercenary_game_ready_three_quarter", (2.55, -3.35, 1.58), (0.0, 0.0, 1.03), 72, (1000, 900))
render_perspective("mercenary_game_ready_portrait", (0.65, -1.68, 1.70), (0.0, -0.015, 1.60), 96, (900, 900))


# Save the editable Rigify scene.
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print("SAVED_BLEND", BLEND_PATH)


# Export only the stable root, generated Rigify skeleton and skinned render meshes.
bpy.ops.object.select_all(action="DESELECT")
character_root.select_set(True)
rig.select_set(True)
for obj in character_meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig

properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
gltf_args = {
    "filepath": GLB_PATH,
    "export_format": "GLB",
    "export_yup": True,
    "export_cameras": False,
    "export_lights": False,
    "export_extras": True,
    "export_materials": "EXPORT",
    "export_image_format": "AUTO",
    "export_animations": False,
}
optional = {
    "use_selection": True,
    "export_selected": True,
    "export_skins": True,
    "export_def_bones": True,
    "export_armature_object_remove": True,
    "export_apply": False,
    "export_morph": False,
    "export_tangents": True,
}
for key, value in optional.items():
    if key in properties:
        gltf_args[key] = value
bpy.ops.export_scene.gltf(**gltf_args)
print("EXPORTED_GLB", GLB_PATH)


# Machine-readable build summary used by the independent QA step.
import json

summary_path = os.path.join(STAGING_DIR, "build_summary.json")
summary = {
    "asset": "mercenary_crossbowman_game_ready_3d",
    "height_m": 1.78,
    "rest_pose": "T_POSE",
    "rig": "Rigify generated rig",
    "triangles": triangle_total,
    "triangle_breakdown": triangle_breakdown,
    "mesh_count": len(character_meshes),
    "deform_bones": len(deform_names),
    "textures": {
        material.name: material.get("texture_set_resolution", 0)
        for material in (mat_skin, mat_gambeson, mat_outer, mat_cowl, mat_leather, mat_hair)
    },
    "excluded": ["crossbow", "sword", "dagger", "quiver", "arrows", "pouches", "scabbards"],
    "blend": BLEND_PATH,
    "glb": GLB_PATH,
}
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, ensure_ascii=False, indent=2)
print("BUILD_SUMMARY", json.dumps(summary, ensure_ascii=False))
