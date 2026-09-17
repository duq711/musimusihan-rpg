import bpy
import json
import math
import os
import struct
from mathutils import Vector


WORKSPACE = os.getcwd()
STAGING_DIR = os.path.join(
    WORKSPACE, "asset-staging", "blender_mercenary_crossbowman_game_ready"
)
TEXTURE_DIR = os.path.join(STAGING_DIR, "textures")
PREVIEW_DIR = os.path.join(STAGING_DIR, "previews")
MPFB_BLEND = os.path.join(STAGING_DIR, "mpfb_base_test.blend")
DONOR_GLB = os.path.join(STAGING_DIR, "triposr", "mercenary_tpose_triposr_raw.glb")
BLEND_PATH = os.path.join(STAGING_DIR, "mercenary_crossbowman_game_ready_v2.blend")
GLB_PATH = os.path.join(
    WORKSPACE,
    "godot-game/assets/3d/dark_fantasy/mercenary_crossbowman_game_ready_3d.glb",
)
SUMMARY_PATH = os.path.join(STAGING_DIR, "build_summary_v2.json")

TARGET_HEIGHT = 1.78
TARGET_TRIANGLES = 125000
SIDE_NORMAL_THRESHOLD = 0.42
FRONT_BBOX = (417, 3677, 241, 3860)
BACK_BBOX = (358, 3740, 239, 3854)
IMAGE_SIZE = 4096.0

os.makedirs(PREVIEW_DIR, exist_ok=True)
os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)


def require_file(path):
    if not os.path.isfile(path):
        raise FileNotFoundError(path)


for required in (
    MPFB_BLEND,
    DONOR_GLB,
    os.path.join(TEXTURE_DIR, "reference_projection_front_basecolor_4k.png"),
    os.path.join(TEXTURE_DIR, "reference_projection_back_basecolor_4k.png"),
):
    require_file(required)


def set_input(node, name, value):
    socket = node.inputs.get(name) if node else None
    if socket is not None:
        socket.default_value = value


def triangle_count(obj):
    if obj.type != "MESH":
        return 0
    return sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)


def set_smooth(obj):
    if obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True


def apply_modifier(obj, modifier):
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def object_world_bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return (
        min(point.x for point in points),
        max(point.x for point in points),
        min(point.y for point in points),
        max(point.y for point in points),
        min(point.z for point in points),
        max(point.z for point in points),
    )


def bake_world_transform(obj):
    matrix = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        vertex.co = matrix @ vertex.co
    obj.matrix_world.identity()
    obj.data.update()


def evaluated_mesh_object(source, name, collection):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bpy.context.view_layer.update()
    evaluated = source.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(
        evaluated, preserve_all_data_layers=True, depsgraph=depsgraph
    )
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.matrix_world = source.matrix_world.copy()
    bake_world_transform(obj)
    return obj


def keep_largest_connected_component(obj):
    mesh = obj.data
    vertex_faces = [[] for _ in mesh.vertices]
    for poly in mesh.polygons:
        for index in poly.vertices:
            vertex_faces[index].append(poly.index)
    remaining = set(range(len(mesh.polygons)))
    components = []
    while remaining:
        seed = remaining.pop()
        component = {seed}
        stack = [seed]
        while stack:
            face_index = stack.pop()
            for vertex_index in mesh.polygons[face_index].vertices:
                for neighbor in vertex_faces[vertex_index]:
                    if neighbor in remaining:
                        remaining.remove(neighbor)
                        component.add(neighbor)
                        stack.append(neighbor)
        components.append(component)
    keep = max(components, key=len)
    source_uv = mesh.uv_layers.active
    used = sorted({index for face in keep for index in mesh.polygons[face].vertices})
    remap = {old: new for new, old in enumerate(used)}
    vertices = [mesh.vertices[index].co.copy() for index in used]
    old_polys = [mesh.polygons[index] for index in sorted(keep)]
    faces = [tuple(remap[index] for index in poly.vertices) for poly in old_polys]
    cleaned = bpy.data.meshes.new(mesh.name + "_MainIsland")
    cleaned.from_pydata(vertices, [], faces)
    cleaned.update()
    if source_uv:
        target_uv = cleaned.uv_layers.new(name="UVMap")
        for new_poly, old_poly in zip(cleaned.polygons, old_polys):
            for new_loop, old_loop in zip(new_poly.loop_indices, old_poly.loop_indices):
                target_uv.data[new_loop].uv = source_uv.data[old_loop].uv.copy()
    old_mesh = obj.data
    obj.data = cleaned
    bpy.data.meshes.remove(old_mesh)
    return [len(component) for component in sorted(components, key=len, reverse=True)]


def filter_faces_in_place(obj, keep_predicate):
    mesh = obj.data
    mesh.update()
    selected = []
    removed = 0
    for poly in mesh.polygons:
        center = sum((mesh.vertices[index].co for index in poly.vertices), Vector()) / len(
            poly.vertices
        )
        if keep_predicate(center, poly):
            selected.append(poly)
        else:
            removed += max(1, len(poly.vertices) - 2)
    used = sorted({index for poly in selected for index in poly.vertices})
    remap = {old: new for new, old in enumerate(used)}
    vertices = [mesh.vertices[index].co.copy() for index in used]
    faces = [tuple(remap[index] for index in poly.vertices) for poly in selected]
    filtered = bpy.data.meshes.new(mesh.name + "_FaceFiltered")
    filtered.from_pydata(vertices, [], faces)
    filtered.update()
    old_mesh = obj.data
    obj.data = filtered
    bpy.data.meshes.remove(old_mesh)
    return removed


def subset_mesh_object(source, name, collection, predicate):
    mesh = source.data
    selected = []
    for poly in mesh.polygons:
        center = sum((mesh.vertices[index].co for index in poly.vertices), Vector()) / len(
            poly.vertices
        )
        if predicate(center, poly):
            selected.append(poly)
    used = sorted({index for poly in selected for index in poly.vertices})
    remap = {old: new for new, old in enumerate(used)}
    vertices = [mesh.vertices[index].co.copy() for index in used]
    faces = [tuple(remap[index] for index in poly.vertices) for poly in selected]
    target = bpy.data.meshes.new(name + "_Mesh")
    target.from_pydata(vertices, [], faces)
    target.update()
    source_uv = mesh.uv_layers.active
    if source_uv:
        target_uv = target.uv_layers.new(name="UVMap")
        for new_poly, old_poly in zip(target.polygons, selected):
            for new_loop, old_loop in zip(new_poly.loop_indices, old_poly.loop_indices):
                target_uv.data[new_loop].uv = source_uv.data[old_loop].uv.copy()
    obj = bpy.data.objects.new(name, target)
    collection.objects.link(obj)
    return obj


def load_image(filename, non_color=False):
    image = bpy.data.images.load(os.path.join(TEXTURE_DIR, filename), check_existing=True)
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    return image


def make_projection_material(name, filename):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "ReferenceProjection_4K"
    texture.image = load_image(filename)
    texture.interpolation = "Linear"
    texture.extension = "EXTEND"
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    emission = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
    if emission is not None:
        links.new(texture.outputs["Color"], emission)
    set_input(bsdf, "Emission Strength", 0.18)
    set_input(bsdf, "Roughness", 0.86)
    set_input(bsdf, "Metallic", 0.0)
    set_input(bsdf, "Specular IOR Level", 0.20)
    set_input(bsdf, "IOR", 1.38)
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    material["texture_set_resolution"] = 4096
    material["projection_bbox"] = str(FRONT_BBOX if "Front" in name else BACK_BBOX)
    return material


def make_pbr_material(name, prefix, normal_strength=0.55):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
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
    for texture in (base, normal, orm):
        texture.extension = "REPEAT"
        texture.interpolation = "Linear"
    base.name = "BaseColor_4K"
    normal.name = "Normal_4K"
    orm.name = "ORM_4K"
    normal_map.inputs["Strength"].default_value = normal_strength
    links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(orm.outputs["Color"], separate.inputs["Color"])
    links.new(separate.outputs["Green"], bsdf.inputs["Roughness"])
    set_input(bsdf, "Specular IOR Level", 0.30)
    set_input(bsdf, "IOR", 1.45)
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    material["texture_set_resolution"] = 4096
    material["texture_set_prefix"] = prefix
    return material


def make_simple_material(name, color, roughness=0.55, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    material.diffuse_color = color
    set_input(bsdf, "Base Color", color)
    set_input(bsdf, "Roughness", roughness)
    set_input(bsdf, "Metallic", metallic)
    return material


def make_neutral_eye_material():
    material = bpy.data.materials.new("MAT_Eyes_Neutral_DarkBrown")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    texture = nodes.new("ShaderNodeTexImage")
    hue = nodes.new("ShaderNodeHueSaturation")
    texture.image = bpy.data.images.load(
        os.path.join(
            STAGING_DIR,
            "_mpfb_cc0_preview_assets/eyes/materials/brown_eye.png",
        ),
        check_existing=True,
    )
    texture.interpolation = "Linear"
    hue.inputs["Saturation"].default_value = 0.22
    hue.inputs["Value"].default_value = 0.95
    links.new(texture.outputs["Color"], hue.inputs["Color"])
    links.new(hue.outputs["Color"], bsdf.inputs["Base Color"])
    set_input(bsdf, "Roughness", 0.28)
    set_input(bsdf, "Specular IOR Level", 0.42)
    set_input(bsdf, "IOR", 1.38)
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    material["texture_set_resolution"] = 1024
    return material


def side_material_index(center, side_role):
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
    return 4  # torso outer wool


def assign_projection_uv_and_materials(obj, materials, x_bounds, z_bounds, side_role):
    mesh = obj.data
    mesh.materials.clear()
    for material in materials:
        mesh.materials.append(material)
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    xmin, xmax = x_bounds
    zmin, zmax = z_bounds
    xspan = max(1e-8, xmax - xmin)
    zspan = max(1e-8, zmax - zmin)
    mesh.update()
    front_faces = back_faces = side_faces = 0
    for poly in mesh.polygons:
        center = poly.center
        normal = poly.normal
        # The MPFB nose, eye sockets and cheeks contain grazing normals; treating
        # those as side faces creates a visible material seam. The whole frontal
        # facial shell is therefore projected from the front regardless of normal.
        force_head_front = (
            side_role == "head" and center.z > 1.43 and center.y < -0.02
        )
        local_threshold = (
            0.68
            if side_role == "donor" and center.z > 1.42
            else SIDE_NORMAL_THRESHOLD
        )
        if force_head_front or normal.y < -local_threshold:
            poly.material_index = 0
            bbox = FRONT_BBOX
            front_faces += 1
            x0, x1, y0, y1 = bbox
            u0, u1 = x0 / IMAGE_SIZE, x1 / IMAGE_SIZE
            v0, v1 = 1.0 - y1 / IMAGE_SIZE, 1.0 - y0 / IMAGE_SIZE
            for loop_index in poly.loop_indices:
                co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                norm_x = (co.x - xmin) / xspan
                norm_z = (co.z - zmin) / zspan
                uv.data[loop_index].uv = (
                    u0 + (1.0 - norm_x) * (u1 - u0),
                    v0 + norm_z * (v1 - v0),
                )
        elif normal.y > local_threshold:
            poly.material_index = 1
            bbox = BACK_BBOX
            back_faces += 1
            x0, x1, y0, y1 = bbox
            u0, u1 = x0 / IMAGE_SIZE, x1 / IMAGE_SIZE
            v0, v1 = 1.0 - y1 / IMAGE_SIZE, 1.0 - y0 / IMAGE_SIZE
            for loop_index in poly.loop_indices:
                co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                norm_x = (co.x - xmin) / xspan
                norm_z = (co.z - zmin) / zspan
                uv.data[loop_index].uv = (
                    u0 + (1.0 - norm_x) * (u1 - u0),
                    v0 + norm_z * (v1 - v0),
                )
        else:
            poly.material_index = side_material_index(center, side_role)
            side_faces += 1
            for loop_index in poly.loop_indices:
                co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                if abs(normal.z) > abs(normal.x):
                    side_u, side_v = co.x * 4.0, co.y * 4.0
                else:
                    side_u, side_v = co.y * 4.0, co.z * 4.0
                uv.data[loop_index].uv = (side_u, side_v)
    mesh.update()
    obj["projection_faces_front"] = front_faces
    obj["projection_faces_back"] = back_faces
    obj["procedural_pbr_side_faces"] = side_faces
    obj["side_normal_threshold"] = SIDE_NORMAL_THRESHOLD
    return {"front": front_faces, "back": back_faces, "side": side_faces}


def normalize_object_set(objects, bounds):
    xmin, xmax, ymin, ymax, zmin, zmax = bounds
    scale = TARGET_HEIGHT / max(1e-8, zmax - zmin)
    center_x = (xmin + xmax) * 0.5
    center_y = (ymin + ymax) * 0.5
    for obj in objects:
        for vertex in obj.data.vertices:
            vertex.co.x = (vertex.co.x - center_x) * scale
            vertex.co.y = (vertex.co.y - center_y) * scale
            vertex.co.z = (vertex.co.z - zmin) * scale
        obj.data.update()
    return scale


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def make_eye_disk(name, location, radius, depth, collection):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=32,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)
    bake_world_transform(obj)
    uv = obj.data.uv_layers.new(name="UVMap")
    for poly in obj.data.polygons:
        for loop_index in poly.loop_indices:
            co = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = (
                0.5 + (co.x - location[0]) / (2.0 * radius),
                0.5 + (co.z - location[2]) / (2.0 * radius),
            )
    triangulate = obj.modifiers.new("EyeDisk_Triangulate", "TRIANGULATE")
    apply_modifier(obj, triangulate)
    obj["game_asset"] = True
    obj["part_category"] = "Eyes"
    obj["source"] = "Procedural neutral iris"
    return obj


def glb_json_and_stats(path):
    with open(path, "rb") as handle:
        header = handle.read(12)
        magic, version, _ = struct.unpack("<4sII", header)
        if magic != b"glTF" or version != 2:
            raise RuntimeError("Not a glTF 2 GLB")
        document = None
        while True:
            chunk_header = handle.read(8)
            if not chunk_header:
                break
            chunk_length, chunk_type = struct.unpack("<II", chunk_header)
            data = handle.read(chunk_length)
            if chunk_type == 0x4E4F534A:
                document = json.loads(data.decode("utf-8").rstrip("\x00 \t\r\n"))
        if document is None:
            raise RuntimeError("GLB JSON chunk missing")
    accessors = document.get("accessors", [])
    triangles = 0
    primitive_count = 0
    joint_primitives = 0
    weight_primitives = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            primitive_count += 1
            attributes = primitive.get("attributes", {})
            joint_primitives += int("JOINTS_0" in attributes)
            weight_primitives += int("WEIGHTS_0" in attributes)
            if primitive.get("mode", 4) == 4:
                if "indices" in primitive:
                    triangles += accessors[primitive["indices"]]["count"] // 3
                elif "POSITION" in attributes:
                    triangles += accessors[attributes["POSITION"]]["count"] // 3
    skins = document.get("skins", [])
    stats = {
        "skins": len(skins),
        "skin_joint_counts": [len(skin.get("joints", [])) for skin in skins],
        "joint_nodes_total": sum(len(skin.get("joints", [])) for skin in skins),
        "mesh_primitives": primitive_count,
        "joint_primitives": joint_primitives,
        "weight_primitives": weight_primitives,
        "triangles": triangles,
        "images": len(document.get("images", [])),
        "textures": len(document.get("textures", [])),
        "materials": len(document.get("materials", [])),
    }
    if not skins or not joint_primitives or not weight_primitives:
        raise RuntimeError("Exported GLB is missing real skin/JOINTS_0/WEIGHTS_0 data")
    return document, stats


# Clean, deterministic scene, including hidden objects from any startup file.
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.images):
    for block in list(datablocks):
        if block.users == 0:
            datablocks.remove(block)

scene = bpy.context.scene
asset_collection = bpy.data.collections.new("Mercenary_GameReady_v2")
scene.collection.children.link(asset_collection)
preview_collection = bpy.data.collections.new("Preview_v2")
scene.collection.children.link(preview_collection)


# Import the TripoSR donor and bake the required raw->world transform:
# raw X and Y are both negated (180 degrees around Z), with the character facing -Y.
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=DONOR_GLB)
imported = [obj for obj in bpy.data.objects if obj not in before]
donor = max((obj for obj in imported if obj.type == "MESH"), key=lambda obj: len(obj.data.vertices))
for obj in imported:
    if obj != donor:
        bpy.data.objects.remove(obj, do_unlink=True)
for collection in list(donor.users_collection):
    collection.objects.unlink(donor)
asset_collection.objects.link(donor)
donor.name = "Mercenary_Clothed_Donor_LOD0"
world_points = [donor.matrix_world @ vertex.co for vertex in donor.data.vertices]
for vertex, point in zip(donor.data.vertices, world_points):
    vertex.co = (-point.x, -point.y, point.z)
donor.matrix_world.identity()
donor.data.update()
donor_islands = keep_largest_connected_component(donor)

raw_bounds = object_world_bounds(donor)
raw_height = raw_bounds[5] - raw_bounds[4]
raw_center_x = (raw_bounds[0] + raw_bounds[1]) * 0.5
raw_center_y = (raw_bounds[2] + raw_bounds[3]) * 0.5
height_scale = TARGET_HEIGHT / raw_height
for vertex in donor.data.vertices:
    vertex.co.x = (vertex.co.x - raw_center_x) * height_scale
    vertex.co.y = (vertex.co.y - raw_center_y) * height_scale
    vertex.co.z = (vertex.co.z - raw_bounds[4]) * height_scale
donor.data.update()


# Append only the MPFB source objects needed to derive a photoreal head, eyes and brows.
mpfb_names = [
    "Mercenary_Male_Body",
    "Mercenary_Male_Eyes",
    "Mercenary_Male_Eyebrows",
    "Mercenary_Male_Hair",
    "Mercenary_Male_Rig",
    "Mercenary_Male_MetaRig",
]
with bpy.data.libraries.load(MPFB_BLEND, link=False) as (data_from, data_to):
    data_to.objects = [name for name in mpfb_names if name in data_from.objects]
mpfb_sources = {}
for obj in data_to.objects:
    if obj is not None:
        asset_collection.objects.link(obj)
        mpfb_sources[obj.name] = obj
for name in mpfb_names:
    if name not in mpfb_sources:
        raise RuntimeError("MPFB source object missing: " + name)

source_body = mpfb_sources["Mercenary_Male_Body"]
source_eyes = mpfb_sources["Mercenary_Male_Eyes"]
source_brows = mpfb_sources["Mercenary_Male_Eyebrows"]
full_body = evaluated_mesh_object(source_body, "_MPFB_VisibleBody_Evaluated", asset_collection)
eyes = evaluated_mesh_object(source_eyes, "Mercenary_Eyes_GameReady", asset_collection)
brows = evaluated_mesh_object(source_brows, "Mercenary_Eyebrows_GameReady", asset_collection)
mpfb_bounds = object_world_bounds(full_body)
normalize_object_set((full_body, eyes, brows), mpfb_bounds)
mpfb_visible_width = max(vertex.co.x for vertex in full_body.data.vertices) - min(
    vertex.co.x for vertex in full_body.data.vertices
)

# Match the donor arm span to the normalized MPFB T-pose while preserving 1.78m height.
donor_bounds = object_world_bounds(donor)
donor_width = donor_bounds[1] - donor_bounds[0]
arm_width_scale = mpfb_visible_width / max(1e-8, donor_width)
for vertex in donor.data.vertices:
    vertex.co.x *= arm_width_scale
donor.data.update()

# Retain the central MPFB head and neck only. The evaluated mesh keeps MPFB's face detail.
head = subset_mesh_object(
    full_body,
    "Mercenary_Male_HeadNeck_LOD0",
    asset_collection,
    lambda center, poly: center.z > 1.355 and abs(center.x) < 0.145,
)
bpy.data.objects.remove(full_body, do_unlink=True)

# Place the MPFB face just in front of the donor face, leaving the donor hair/cowl silhouette.
donor_front_samples = [
    vertex.co.y
    for vertex in donor.data.vertices
    if 1.48 < vertex.co.z < 1.73 and abs(vertex.co.x) < 0.075
]
head_front_samples = [
    vertex.co.y
    for vertex in head.data.vertices
    if 1.48 < vertex.co.z < 1.73 and abs(vertex.co.x) < 0.075
]
if donor_front_samples and head_front_samples:
    face_shift_y = min(donor_front_samples) - min(head_front_samples) - 0.010
else:
    face_shift_y = -0.055
for obj in (head, eyes, brows):
    for vertex in obj.data.vertices:
        vertex.co.y += face_shift_y
    obj.data.update()

# Remove the duplicate eyebrow cards: the 4K face projection already contains
# the intended brows. Keep the MPFB eyes at their original socket depth.
bpy.data.objects.remove(brows, do_unlink=True)
brows = None

# Deterministic neutral eyes: retain the MPFB eyeballs as warm sclera and add
# explicit dark-brown irises plus smaller black pupils at each -Y/front pole.
eye_disks = []
for suffix, side_predicate in (("L", lambda x: x >= 0.0), ("R", lambda x: x < 0.0)):
    points = [vertex.co for vertex in eyes.data.vertices if side_predicate(vertex.co.x)]
    if not points:
        raise RuntimeError("Could not isolate MPFB eye side " + suffix)
    cx = (min(point.x for point in points) + max(point.x for point in points)) * 0.5
    cz = (min(point.z for point in points) + max(point.z for point in points)) * 0.5
    front_y = min(point.y for point in points)
    iris = make_eye_disk(
        "Mercenary_Iris_" + suffix,
        (cx, front_y + 0.00025, cz),
        0.0050,
        0.0006,
        asset_collection,
    )
    pupil = make_eye_disk(
        "Mercenary_Pupil_" + suffix,
        (cx, front_y + 0.00008, cz),
        0.0022,
        0.0005,
        asset_collection,
    )
    eye_disks.extend((iris, pupil))

# Remove the donor's front-center facial shell so the MPFB face cannot z-fight or
# be occluded. Keep the upper/side hair mass and the surrounding cowl silhouette.
donor_face_triangles_removed = filter_faces_in_place(
    donor,
    lambda center, poly: not (
        1.46 < center.z < 1.73
        and abs(center.x) < 0.17
        and center.y < 0.0
    ),
)

# Remove the appended MPFB rig/metarig and clean hair, plus their source meshes.
for name in mpfb_names:
    source = mpfb_sources.get(name)
    if source and source.name in bpy.data.objects:
        bpy.data.objects.remove(source, do_unlink=True)
for _ in range(3):
    try:
        bpy.ops.outliner.orphans_purge(do_recursive=True)
    except Exception:
        break


# Refine the donor once with Catmull-Clark, then decimate dynamically around 125k total.
subdivision = donor.modifiers.new("TripoSR_CatmullRefine", "SUBSURF")
subdivision.subdivision_type = "CATMULL_CLARK"
subdivision.levels = 1
subdivision.render_levels = 1
subdivision.show_only_control_edges = True
apply_modifier(donor, subdivision)
fixed_triangles = triangle_count(head) + triangle_count(eyes) + sum(
    triangle_count(obj) for obj in eye_disks
)
donor_target = max(65000, TARGET_TRIANGLES - fixed_triangles)
donor_refined_triangles = triangle_count(donor)
if donor_refined_triangles > donor_target:
    decimate = donor.modifiers.new("LOD0_Target_125K", "DECIMATE")
    decimate.decimate_type = "COLLAPSE"
    decimate.ratio = max(0.05, min(1.0, donor_target / donor_refined_triangles))
    decimate.use_collapse_triangulate = True
    apply_modifier(donor, decimate)
set_smooth(donor)
set_smooth(head)
set_smooth(eyes)


# Projection and side PBR materials. Material index order is used by side_material_index().
mat_front = make_projection_material(
    "MAT_ReferenceProjection_Front_4K", "reference_projection_front_basecolor_4k.png"
)
mat_back = make_projection_material(
    "MAT_ReferenceProjection_Back_4K", "reference_projection_back_basecolor_4k.png"
)
mat_skin = make_pbr_material("MAT_Skin_Side_PBR_4K", "skin", 0.52)
mat_gambeson = make_pbr_material("MAT_Gambeson_Side_PBR_4K", "gambeson", 0.68)
mat_outer = make_pbr_material("MAT_OuterWool_Side_PBR_4K", "outer_wool", 0.72)
mat_cowl = make_pbr_material("MAT_CowlWool_Side_PBR_4K", "cowl_wool", 0.70)
mat_leather = make_pbr_material("MAT_Leather_Side_PBR_4K", "leather", 0.62)
all_surface_materials = [
    mat_front,
    mat_back,
    mat_skin,
    mat_gambeson,
    mat_outer,
    mat_cowl,
    mat_leather,
]
donor_bounds = object_world_bounds(donor)
projection_x_bounds = (donor_bounds[0], donor_bounds[1])
projection_z_bounds = (0.0, TARGET_HEIGHT)
projection_counts = {
    donor.name: assign_projection_uv_and_materials(
        donor, all_surface_materials, projection_x_bounds, projection_z_bounds, "donor"
    ),
    head.name: assign_projection_uv_and_materials(
        head, all_surface_materials, projection_x_bounds, projection_z_bounds, "head"
    ),
}

# Replace the red-biased source eyes with deterministic neutral components.
eyes.data.materials.clear()
eyes.data.materials.append(
    make_simple_material("MAT_Eyes_WarmSclera", (0.22, 0.16, 0.12, 1.0), 0.30)
)
mat_iris = make_simple_material("MAT_Eyes_DarkBrownIris", (0.050, 0.016, 0.006, 1.0), 0.34)
mat_pupil = make_simple_material("MAT_Eyes_BlackPupil", (0.003, 0.002, 0.001, 1.0), 0.16)
for obj in eye_disks:
    obj.data.materials.append(mat_iris if "Iris" in obj.name else mat_pupil)

for obj, category in (
    (donor, "ClothedBody"),
    (head, "Face"),
    (eyes, "Eyes"),
):
    obj["game_asset"] = True
    obj["part_category"] = category
    obj["source"] = "TripoSR" if obj == donor else "MPFB_CC0"


# Fresh Rigify full body rig, conformed to the 1.78m T-pose and actual arm span.
bpy.ops.preferences.addon_enable(module="rigify")
bpy.ops.object.select_all(action="DESELECT")
bpy.ops.object.armature_human_metarig_add()
metarig = bpy.context.active_object
metarig.name = "metarig_mercenary_v2"
metarig.data.name = "metarig_mercenary_v2"
metarig.scale = (TARGET_HEIGHT / 1.9796,) * 3
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
metarig.data.rigify_rig_basename = "mercenary_v2_rig"

bpy.context.view_layer.objects.active = metarig
bpy.ops.object.mode_set(mode="EDIT")
body_extent_x = max(abs(vertex.co.x) for vertex in donor.data.vertices)
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
    local_u = sign * (reference.x - pivot.x)
    theta = math.atan2(reference.z - pivot.z, max(1e-6, local_u))

    def rotate_arm_point(point):
        delta = point - pivot
        axis_u = sign * delta.x
        new_u = math.cos(theta) * axis_u + math.sin(theta) * delta.z
        new_z = -math.sin(theta) * axis_u + math.cos(theta) * delta.z
        return pivot + Vector((sign * new_u, delta.y, new_z))

    for bone in descendants:
        bone.head = rotate_arm_point(bone.head)
        bone.tail = rotate_arm_point(bone.tail)
    current_extent = max(
        sign * (point.x - pivot.x)
        for bone in descendants
        for point in (bone.head, bone.tail)
    )
    target_extent = max(0.40, body_extent_x * 0.965 - sign * pivot.x)
    stretch = target_extent / max(current_extent, 1e-5)
    for bone in descendants:
        for attribute in ("head", "tail"):
            point = getattr(bone, attribute).copy()
            point.x = pivot.x + (point.x - pivot.x) * stretch
            setattr(bone, attribute, point)
    # Exact T-pose: every arm, hand and finger rest bone lies on the shoulder plane.
    for bone in descendants:
        bone.head.z = pivot.z
        bone.tail.z = pivot.z
bpy.ops.object.mode_set(mode="OBJECT")

arm_rest_delta = 0.0
for name in ("upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"):
    bone = metarig.data.bones.get(name)
    if bone:
        arm_rest_delta = max(arm_rest_delta, abs(bone.tail_local.z - bone.head_local.z))

armatures_before = {obj for obj in scene.objects if obj.type == "ARMATURE"}
bpy.context.view_layer.objects.active = metarig
metarig.select_set(True)
bpy.ops.pose.rigify_generate()
generated = [
    obj
    for obj in scene.objects
    if obj.type == "ARMATURE" and obj not in armatures_before and obj != metarig
]
if not generated:
    raise RuntimeError("Rigify did not generate an armature")
rig = max(generated, key=lambda obj: len(obj.data.bones))
rig.name = "Mercenary_Rigify_Rig_v2"
rig.data.name = "Mercenary_Rigify_Skeleton_v2"
rig["rig_system"] = "Rigify"
rig["rest_pose"] = "T_POSE"
rig["height_m"] = TARGET_HEIGHT
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
    x, _, z = co
    if category in {"Face", "Eyes", "Hair"}:
        return {"DEF-spine.006": 1.0}
    groups = {}
    side = "L" if x >= 0.0 else "R"
    ax = abs(x)
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
        elif ax < 0.775:
            t = normalized_blend(ax, 0.650, 0.775)
            add_weight(groups, "DEF-forearm." + side, 1.0 - t * 0.70)
            add_weight(groups, "DEF-forearm." + side + ".001", t * 0.70)
        else:
            t = normalized_blend(ax, 0.775, body_extent_x)
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


character_meshes = [donor, head, eyes] + eye_disks
for obj in character_meshes:
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    group_cache = {}
    category = obj["part_category"]
    for vertex in obj.data.vertices:
        for bone_name, weight in weights_for_coordinate(vertex.co, category).items():
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

for collection in bpy.data.collections:
    if collection.name.startswith("WGTS") or collection.name.startswith("WGT"):
        collection.hide_render = True
        collection.hide_viewport = True
for obj in scene.objects:
    if obj.name.startswith("WGT-"):
        obj.hide_render = True
        obj.hide_viewport = True
rig.hide_render = True


# Neutral, low-specular studio preserving the reference projection's dark contrast.
scene.world.color = (0.008, 0.008, 0.010)
bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, -0.008))
ground = bpy.context.object
ground.name = "PREVIEW_v2_Ground"
for collection in list(ground.users_collection):
    collection.objects.unlink(ground)
preview_collection.objects.link(ground)
ground.data.materials.append(
    make_simple_material("MAT_PREVIEW_v2_Ground", (0.028, 0.031, 0.036, 1.0), 0.88)
)


def add_area_light(name, location, energy, color, size, target=(0.0, 0.0, 0.95)):
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


add_area_light("PREVIEW_v2_Key", (2.7, -4.2, 3.2), 410.0, (1.0, 0.86, 0.74), 3.2)
add_area_light("PREVIEW_v2_Fill", (-3.2, -2.3, 2.2), 175.0, (0.60, 0.70, 1.0), 3.8)
add_area_light("PREVIEW_v2_Rim", (1.0, 3.6, 3.0), 330.0, (1.0, 0.66, 0.48), 2.7)
add_area_light("PREVIEW_v2_Top", (0.0, 0.0, 4.5), 160.0, (1.0, 0.93, 0.84), 2.8)

camera_data = bpy.data.cameras.new("PREVIEW_v2_CameraData")
camera = bpy.data.objects.new("PREVIEW_v2_Camera", camera_data)
preview_collection.objects.link(camera)
scene.camera = camera
try:
    scene.render.engine = "BLENDER_EEVEE_NEXT"
except Exception:
    scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.render.image_settings.compression = 25
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = -0.15


preview_paths = {}


def render_orthographic(key, location, target, ortho_scale, resolution=(1200, 1200)):
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = os.path.join(PREVIEW_DIR, "mercenary_game_ready_v2_" + key + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = path
    print("RENDERED", path)


def render_perspective(key, location, target, lens, resolution=(1100, 1100)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = os.path.join(PREVIEW_DIR, "mercenary_game_ready_v2_" + key + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = path
    print("RENDERED", path)


render_orthographic("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render_orthographic("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render_perspective("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.00), 72)
render_perspective("portrait", (0.42, -1.42, 1.69), (0.0, -0.03, 1.61), 92)


# Save editable source, then export the real skinned Godot GLB.
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print("SAVED_BLEND", BLEND_PATH)

bpy.ops.object.select_all(action="DESELECT")
rig.hide_set(False)
rig.select_set(True)
for obj in character_meshes:
    obj.hide_set(False)
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
    "export_armature_object_remove": False,
    "export_rest_position_armature": True,
    "export_all_influences": False,
    "export_influence_nb": 4,
    "export_leaf_bone": False,
    "export_texcoords": True,
    "export_normals": True,
    "export_apply": False,
    "export_morph": False,
    "export_tangents": True,
}
for key, value in optional.items():
    if key in properties:
        gltf_args[key] = value
print("GLTF_EXPORT_ARGS", gltf_args)
bpy.ops.export_scene.gltf(**gltf_args)
print("EXPORTED_GLB", GLB_PATH)

_, glb_stats = glb_json_and_stats(GLB_PATH)
triangle_breakdown = {obj.name: triangle_count(obj) for obj in character_meshes}
triangle_total = sum(triangle_breakdown.values())
if not 100000 <= triangle_total <= 150000:
    raise RuntimeError("Triangle budget out of range: %d" % triangle_total)

summary = {
    "asset": "mercenary_crossbowman_game_ready_v2",
    "height_m": TARGET_HEIGHT,
    "rest_pose": "T_POSE",
    "neutral_expression": True,
    "front_axis": "-Y",
    "raw_to_world": "x=-raw_x, y=-raw_y, z=raw_z (180deg Z)",
    "rig": "Fresh Rigify full rig",
    "deform_bones": len(deform_names),
    "arm_rest_max_vertical_delta_m": arm_rest_delta,
    "triangles": triangle_total,
    "triangle_breakdown": triangle_breakdown,
    "mesh_count": len(character_meshes),
    "donor_connected_island_face_counts": donor_islands,
    "donor_front_face_triangles_removed": donor_face_triangles_removed,
    "donor_refine": "Catmull-Clark level 1 then dynamic collapse decimation",
    "donor_arm_width_scale": arm_width_scale,
    "mpfb_head_face_shift_y_m": face_shift_y,
    "projection": {
        "front_bbox_4096": FRONT_BBOX,
        "back_bbox_4096": BACK_BBOX,
        "u_mapping": "1-normalized_world_x",
        "side_normal_threshold": SIDE_NORMAL_THRESHOLD,
        "counts": projection_counts,
        "side_faces": "spatial 4K PBR UV tiling; no front/back projection",
    },
    "textures": {
        "front_projection": 4096,
        "back_projection": 4096,
        "skin": 4096,
        "gambeson": 4096,
        "outer_wool": 4096,
        "cowl_wool": 4096,
        "leather": 4096,
    },
    "excluded": [
        "crossbow",
        "sword",
        "dagger",
        "quiver",
        "arrows",
        "pouches",
        "scabbards",
        "MPFB clean hair",
        "MPFB source rig",
        "MPFB source metarig",
    ],
    "gltf_export": {
        "export_armature_object_remove": False,
        "export_skins": True,
        "export_def_bones": True,
        "export_rest_position_armature": True,
        "export_all_influences": False,
        "export_influence_nb": 4,
    },
    "glb_self_check": glb_stats,
    "previews": preview_paths,
    "blend": BLEND_PATH,
    "glb": GLB_PATH,
}
with open(SUMMARY_PATH, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, ensure_ascii=False, indent=2)
print("BUILD_SUMMARY_V2", json.dumps(summary, ensure_ascii=False))
