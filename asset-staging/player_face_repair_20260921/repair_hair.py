"""Unify the preserved head's short hair without altering facial geometry.

Call repair_face() first: 72 nose triangles were incorrectly assigned to the
old crown material. This helper owns the remaining three hair materials and
the upper forehead transition band listed in its report. It creates one
packed 1K albedo and an ordinary glTF-compatible Principled material;
it never opens/saves a blend, adds geometry, exports, or renders.
"""
from pathlib import Path
import hashlib
import json
import math

import bpy
import numpy as np

W = Path(__file__).resolve().parent
HAIR_NAMES = (
    "Gravebound_Unhooded_Hair_ScalpNeutralBrown_2K_v16j",
    "Gravebound_Unhooded_ScalpHair_DarkBrown_PBR_2K_v11",
    "Gravebound_Unhooded_Hair_BackShellMatched_2K_v16j",
)
MATERIAL_NAME = "Gravebound_ShortHair_NaturalDarkBrown_PBR"
IMAGE_NAME = "Gravebound_ShortHair_Hairline_1024.png"


def _geometry_signature(mesh):
    data = {
        "vertices": [list(v.co) for v in mesh.vertices],
        "faces": [list(p.vertices) for p in mesh.polygons],
    }
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def hair_face_mask(head):
    """Return exact scalp/crown indices; do not classify skin by pixel color."""
    mesh = head.data
    slots = [i for i, mat in enumerate(mesh.materials)
             if mat and any(mat.name.startswith(name) for name in HAIR_NAMES)]
    assert len(slots) == 3, ("Expected three authored scalp materials", slots)
    nose = [p.index for p in mesh.polygons if p.material_index in slots
            and abs(p.center.x) < .015 and p.center.y < -.10
            and p.center.z < 1.63]
    assert not nose, "Run repair_face() before repair_hair(): nose is still misclassified"
    scalp = [p.index for p in mesh.polygons if p.material_index in slots]
    crown = [p.index for p in mesh.polygons
             if "ReferenceProjection_Front" in mesh.materials[p.material_index].name
             and p.center.z > 1.630 and abs(p.center.x) < .095]
    assert len(scalp) == 4963, ("Scalp mask changed", len(scalp))
    assert len(crown) == 1227, ("Upper forehead transition mask changed", len(crown))
    return slots, scalp, crown


def _short_hair_image(source):
    """Bake a compact opaque color patch from the existing authored hair map.

    The bounded lower-island patch contains dense short multidirectional
    strands. It excludes the long crown strip map, atlas gutters and cutout
    edges. Lower contrast and restrained warmth suit the game's matte cloth.
    """
    source_pixels = np.empty(len(source.pixels), dtype=np.float32)
    source.pixels.foreach_get(source_pixels)
    width, height = source.size
    source_pixels = source_pixels.reshape(height, width, 4)
    size = 512
    # Blender pixel rows run bottom to top. These bounds remain wholly within
    # the lower short02 hair atlas island's densely covered center.
    u = np.linspace(.32, .55, size, dtype=np.float32) * (width - 1)
    v = np.linspace(.22, .42, size, dtype=np.float32) * (height - 1)
    x0, y0 = np.floor(u).astype(int), np.floor(v).astype(int)
    x1, y1 = np.minimum(x0 + 1, width - 1), np.minimum(y0 + 1, height - 1)
    fx, fy = (u - x0)[None, :, None], (v - y0)[:, None, None]
    bottom = source_pixels[y0[:, None], x0[None, :], :3] * (1 - fx) + source_pixels[y0[:, None], x1[None, :], :3] * fx
    top = source_pixels[y1[:, None], x0[None, :], :3] * (1 - fx) + source_pixels[y1[:, None], x1[None, :], :3] * fx
    rgb = bottom * (1 - fy) + top * fy
    mean = rgb.mean(axis=(0, 1), keepdims=True)
    rgb = np.clip((mean + (rgb - mean) * .66) * np.array([.84, .90, .96]), 0, 1)
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:, :, :3] = rgb
    image = bpy.data.images.new("Gravebound_ShortHair_Strands_512_Working", width=size, height=size, alpha=True)
    image.colorspace_settings.name = source.colorspace_settings.name
    image.pixels.foreach_set(rgba.reshape(-1))
    image.update()
    image.pack()
    assert image.packed_file and list(image.size) == [512, 512]
    return image, {
        "source_image": source.name,
        "source_size": [width, height],
        "source_crop_uv": [.32, .22, .55, .42],
        "crop_mean_rgb": mean.reshape(-1).tolist(),
        "output_mean_rgb": rgb.mean(axis=(0, 1)).tolist(),
        "contrast": .66,
        "channel_multiplier": [.84, .90, .96],
        "output_size": [size, size],
        "packed": True,
    }


def _pixels(image):
    data = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(data)
    return data.reshape(image.size[1], image.size[0], 4)


def _sample(pixels, uv):
    height, width = pixels.shape[:2]
    xy = np.clip(uv, 0, 1) * np.array([width - 1, height - 1])
    base = np.floor(xy).astype(int)
    end = np.minimum(base + 1, [width - 1, height - 1])
    fx, fy = (xy - base).T
    a = pixels[base[:, 1], base[:, 0], :3] * (1 - fx[:, None]) + pixels[base[:, 1], end[:, 0], :3] * fx[:, None]
    b = pixels[end[:, 1], base[:, 0], :3] * (1 - fx[:, None]) + pixels[end[:, 1], end[:, 0], :3] * fx[:, None]
    return a * (1 - fy[:, None]) + b * fy[:, None]


def _smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def _bake_hairline(mesh, scalp, transition, strand_image):
    """Rasterize a smooth hair/forehead boundary across existing triangles.

    The domain includes both sides of the old material border. A single
    spatial mask, rather than whole-triangle hair classifications, removes
    the central wedge and stepped front/temple edges. Geometry is unchanged.
    """
    front_mat = next(m for m in mesh.materials if "ReferenceProjection_Front" in m.name)
    front_image = next(n.image for n in front_mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
    front_pixels, strand_pixels = _pixels(front_image), _pixels(strand_image)
    size = 1024
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:, :, :3] = strand_pixels[:, :, :3].mean(axis=(0, 1))
    radius_map = np.zeros((size, size), dtype=np.float32)
    covered = np.zeros((size, size), dtype=bool)
    transition_set = set(transition)
    selected = set(scalp + transition)
    for polygon in mesh.polygons:
        if polygon.index not in selected:
            continue
        loops = list(polygon.loop_indices)
        for offset in range(1, len(loops) - 1):
            tri = [loops[0], loops[offset], loops[offset + 1]]
            coords = np.array([mesh.vertices[mesh.loops[i].vertex_index].co for i in tri])
            uv = np.array([_scalp_uv(co) for co in [mesh.vertices[mesh.loops[i].vertex_index].co for i in tri]])
            pos = uv * (size - 1)
            lower = np.maximum(np.floor(pos.min(axis=0)).astype(int), 0)
            upper = np.minimum(np.ceil(pos.max(axis=0)).astype(int), size - 1)
            if np.any(upper < lower):
                continue
            x, y = np.meshgrid(np.arange(lower[0], upper[0] + 1), np.arange(lower[1], upper[1] + 1))
            a, b, c = pos
            denom = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(denom) < 1e-8:
                continue
            wa = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / denom
            wb = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / denom
            wc = 1 - wa - wb
            inside = (wa >= -1e-5) & (wb >= -1e-5) & (wc >= -1e-5)
            if not inside.any():
                continue
            weights = np.stack([wa[inside], wb[inside], wc[inside]], axis=1)
            xyz = weights @ coords
            ix, iy = x[inside], y[inside]
            radius = np.linalg.norm((xyz - np.array([0, -.012, 1.61])) / [.091, .113, .115], axis=1)
            visible = radius >= radius_map[iy, ix] - 1e-5
            if not visible.any():
                continue
            weights, xyz, radius, ix, iy = weights[visible], xyz[visible], radius[visible], ix[visible], iy[visible]
            tex_uv = np.stack([ix, iy], axis=1) / (size - 1)
            hair_rgb = _sample(strand_pixels, tex_uv)
            # Rounded front arc, descending gently at both temples. Blend into
            # the preserved rear hairline behind the ears.
            side = np.clip(np.abs(xyz[:, 0]) / .068, 0, 1)
            front_line = 1.651 - .040 * side ** 1.4
            front_weight = 1 - _smooth(-.047, -.020, xyz[:, 1])
            line = front_line * front_weight + 1.520 * (1 - front_weight)
            signed = xyz[:, 2] - line
            # Very small unevenness breaks a mechanically drawn hairline,
            # while the 2 mm blend is below the old triangle-edge scale.
            signed += .00045 * np.sin(xyz[:, 0] * 430 + xyz[:, 1] * 110)
            hair_alpha = _smooth(-.001, .001, signed)
            # Keep the original two-dimensional face projection below a
            # lower short fringe. No invented skin strip or stretched scanline.
            face_uv = np.stack([-.439725589 * xyz[:, 0] + .499223546,
                                .496373541 * xyz[:, 2] + .0849177227], axis=1)
            skin_rgb = _sample(front_pixels, face_uv)
            rgb = skin_rgb * (1 - hair_alpha[:, None]) + hair_rgb * hair_alpha[:, None]
            rgba[iy, ix, :3] = rgb
            radius_map[iy, ix] = radius
            covered[iy, ix] = True
    covered_count = int(covered.sum())
    assert covered_count > 200000, ("Hairline bake coverage unexpectedly small", covered_count)
    # Pad raster boundaries for bilinear filtering. In-image sampling stays
    # continuous across former material borders and never uses atlas gutters.
    for _ in range(8):
        original_covered = covered.copy()
        for dy, dx in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
            shifted = np.roll(original_covered, (dy, dx), axis=(0, 1))
            fill = ~covered & shifted
            rgba[fill] = np.roll(rgba, (dy, dx), axis=(0, 1))[fill]
            covered[fill] = True
    image = bpy.data.images.new(IMAGE_NAME, width=size, height=size, alpha=True)
    image.colorspace_settings.name = front_image.colorspace_settings.name
    image.pixels.foreach_set(rgba.reshape(-1))
    image.update()
    image.pack()
    return image, {
        "output_size": [size, size], "packed": bool(image.packed_file),
        "covered_pixels": covered_count, "edge_padding_pixels": 8,
        "center_hairline_z_m": 1.651, "temple_hairline_z_m": 1.611,
        "boundary_blend_m": .002, "front_transition_faces": len(transition),
        "skin_source": front_image.name,
        "skin_mapping": "original continuous 2D front facial projection; no synthetic forehead fill",
    }


def _scalp_uv(co):
    """One continuous equal-area dome map across all old scalp partitions.

    A disk centered on the crown avoids the old planar front/side seams and
    the radial pole of a latitude/longitude map. The only mathematical pole
    lies below the chin, outside the selected hair surface.
    """
    x, y, z = co.x / .091, (co.y + .012) / .113, (co.z - 1.61) / .115
    length = math.sqrt(x * x + y * y + z * z)
    x, y, z = x / length, y / length, z / length
    radial = math.hypot(x, y)
    if radial < 1e-9:
        return (.5, .5)
    radius = math.sqrt(max(0.0, (1.0 - z) * .5)) * .49
    return (.5 + radius * x / radial, .5 + radius * y / radial)


def repair_hair():
    head = bpy.data.objects["Gravebound_AnatomicalHead"]
    mesh = head.data
    before_geometry = _geometry_signature(mesh)
    before_uv = [tuple(loop.uv) for loop in mesh.uv_layers.active.data]
    before_materials = [mesh.materials[p.material_index] for p in mesh.polygons]
    slots, scalp, crown = hair_face_mask(head)
    selected = set(scalp + crown)
    source_material = next(mesh.materials[i] for i in slots
                           if "BackShellMatched" in mesh.materials[i].name)
    source = next(n.image for n in source_material.node_tree.nodes
                  if n.type == "TEX_IMAGE" and n.image)
    strand_image, strand_report = _short_hair_image(source)
    image, image_report = _bake_hairline(mesh, scalp, crown, strand_image)
    image_report["strand_source"] = strand_report
    material = bpy.data.materials.new(MATERIAL_NAME)
    material.use_nodes = True
    material.use_backface_culling = False
    material.diffuse_color = (.055, .036, .024, 1)
    material.roughness = .88
    tree = material.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    shader = tree.nodes.new("ShaderNodeBsdfPrincipled")
    texture = tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Linear"
    texture.extension = "EXTEND"
    shader.inputs["Roughness"].default_value = .88
    shader.inputs["Metallic"].default_value = 0
    shader.inputs["Specular IOR Level"].default_value = .22
    tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    # All users of these three head slots are included in the mask. Reuse
    # their slots so orphaned 2K hair textures need not enter the GLB export.
    original_names = {str(i): mesh.materials[i].name for i in slots}
    for slot in slots:
        mesh.materials[slot] = material
    active_slot = slots[0]
    for face in mesh.polygons:
        if face.index not in selected:
            continue
        face.material_index = active_slot
        for loop_index in face.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            mesh.uv_layers.active.data[loop_index].uv = _scalp_uv(co)
    mesh.update()
    untouched = [p for p in mesh.polygons if p.index not in selected]
    assert all(mesh.materials[p.material_index] is before_materials[p.index]
               and all(tuple(mesh.uv_layers.active.data[i].uv) == before_uv[i]
                       for i in p.loop_indices) for p in untouched)
    assert _geometry_signature(mesh) == before_geometry
    report = {
        "hair_materials_replaced": original_names,
        "authored_scalp_faces": len(scalp),
        "upper_forehead_transition_faces": len(crown),
        "hair_faces": len(selected),
        "hair_face_indices": sorted(selected),
        "projection_transition_face_indices": crown,
        "untouched_face_neck_polygons": len(untouched),
        "non_hair_uv_and_materials_unchanged": True,
        "geometry_unchanged": True,
        "geometry_sha256": before_geometry,
        "mesh_vertices": len(mesh.vertices),
        "mesh_faces": len(mesh.polygons),
        "added_meshes": 0,
        "material": material.name,
        "texture": image_report,
        "mapping": "continuous equal-area scalp dome with baked curved hairline and forehead transition",
        "pass": True,
    }
    (W / "hair_report.json").write_text(json.dumps(report, indent=2))
    print("HAIR REPAIR PASS", len(selected), "faces; preserved geometry and remaining facial UV/materials")
    return report
