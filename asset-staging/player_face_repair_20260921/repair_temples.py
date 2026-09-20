"""Blend the existing cheek/temple material seams without changing geometry.

Run after repair_face() and repair_hair(), before repair_eyes(). Only the
outer cheeks, skin in front of the ears, and lower temple hair participate.
The center of the face and every other object are preserved. No blend/model
save, export or render is performed here.
"""
from pathlib import Path
import hashlib
import json
import math

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

W = Path(__file__).resolve().parent


def _pixels(image):
    array = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(array)
    return array.reshape(image.size[1], image.size[0], 4)


def _sample(pixels, uv):
    h, w = pixels.shape[:2]
    xy = np.clip(uv, 0, 1) * [w - 1, h - 1]
    lo = np.floor(xy).astype(int)
    hi = np.minimum(lo + 1, [w - 1, h - 1])
    fx, fy = (xy - lo).T
    a = pixels[lo[:, 1], lo[:, 0], :3] * (1 - fx[:, None]) + pixels[lo[:, 1], hi[:, 0], :3] * fx[:, None]
    b = pixels[hi[:, 1], lo[:, 0], :3] * (1 - fx[:, None]) + pixels[hi[:, 1], hi[:, 0], :3] * fx[:, None]
    return a * (1 - fy[:, None]) + b * fy[:, None]


def _smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def _image(material):
    return next(n.image for n in material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image)


def _dome_uv(points):
    p = (points - [0, -.012, 1.61]) / [.091, .113, .115]
    p = p / np.linalg.norm(p, axis=1)[:, None]
    radial = np.maximum(np.linalg.norm(p[:, :2], axis=1), 1e-9)
    radius = np.sqrt(np.maximum(0, (1 - p[:, 2]) * .5)) * .49
    return .5 + p[:, :2] * (radius / radial)[:, None]


def _atlas_uv(co):
    u = .025 + .45 * (co.y + .105) / .20
    if co.x > 0:
        u += .5
    return (u, .025 + .95 * (co.z - 1.420) / .250)


def _geometry(mesh):
    return hashlib.sha256(json.dumps({
        'vertices': [list(v.co) for v in mesh.vertices],
        'faces': [list(p.vertices) for p in mesh.polygons],
    }, sort_keys=True).encode()).hexdigest()


def repair_temples():
    head = bpy.data.objects['Gravebound_AnatomicalHead']
    mesh = head.data
    before_geometry = _geometry(mesh)
    old_uv = [tuple(v.uv) for v in mesh.uv_layers.active.data]
    old_materials = [mesh.materials[p.material_index] for p in mesh.polygons]
    front = next(m for m in mesh.materials if 'ReferenceProjection_Front' in m.name)
    side = next(m for m in mesh.materials if 'Skin_Side_PBR' in m.name)
    hair = next(m for m in mesh.materials if m.name.startswith('Gravebound_ShortHair_NaturalDarkBrown'))
    front_image, side_image, hair_image = _image(front), _image(side), _image(hair)
    front_pixels, side_pixels, hair_pixels = _pixels(front_image), _pixels(side_image), _pixels(hair_image)
    selected = []
    for p in mesh.polygons:
        x, y, z = p.center
        material = mesh.materials[p.material_index]
        in_skin = material is side and .045 < abs(x) < .115 and z > 1.450
        in_cheek = material is front and abs(x) > .048 and y > -.095 and 1.465 < z < 1.642
        in_hair = material is hair and abs(x) > .048 and -.078 < y < .040 and 1.580 < z < 1.642
        if in_skin or in_cheek or in_hair:
            selected.append(p.index)
    selected_set = set(selected)
    assert selected and all(abs(mesh.polygons[i].center.x) > .045 for i in selected)

    # A continuous reference field from the actual side-skin UV surface. Each
    # target vertex samples the same nearest side triangle regardless of its
    # old material, so the former front/side border cannot reappear in color.
    side_faces = [p for p in mesh.polygons if mesh.materials[p.material_index] is side]
    positions = [v.co.copy() for v in mesh.vertices]
    bvh = BVHTree.FromPolygons(positions, [list(p.vertices) for p in side_faces], all_triangles=True)
    vertex_ids = {i for p in mesh.polygons if p.index in selected_set for i in p.vertices}
    side_uv = {}
    for index in vertex_ids:
        point, normal, face_index, distance = bvh.find_nearest(positions[index])
        source = side_faces[face_index]
        loops = list(source.loop_indices)
        assert len(loops) == 3
        uv = [Vector((*old_uv[i], 0)) for i in loops]
        mapped = barycentric_transform(point, *(positions[mesh.loops[i].vertex_index] for i in loops), *uv)
        side_uv[index] = (mapped.x, mapped.y)

    size = 1024
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:, :, :3] = [.20, .13, .09]
    depth = np.zeros((size, size), dtype=np.float32)
    filled = np.zeros((size, size), dtype=bool)
    categories = {'front': 0, 'side': 0, 'hair': 0}
    for p in mesh.polygons:
        if p.index not in selected_set:
            continue
        category = 'front' if old_materials[p.index] is front else 'side' if old_materials[p.index] is side else 'hair'
        categories[category] += 1
        indices = list(p.vertices)
        assert len(indices) == 3
        coords = np.array([positions[i] for i in indices])
        uv = np.array([_atlas_uv(positions[i]) for i in indices])
        pos = uv * (size - 1)
        lo = np.maximum(0, np.floor(pos.min(axis=0)).astype(int))
        hi = np.minimum(size - 1, np.ceil(pos.max(axis=0)).astype(int))
        if np.any(lo > hi):
            continue
        xx, yy = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
        a, b, c = pos
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-8:
            continue
        wa = ((b[1] - c[1]) * (xx - c[0]) + (c[0] - b[0]) * (yy - c[1])) / den
        wb = ((c[1] - a[1]) * (xx - c[0]) + (a[0] - c[0]) * (yy - c[1])) / den
        wc = 1 - wa - wb
        inside = (wa >= -1e-5) & (wb >= -1e-5) & (wc >= -1e-5)
        if not inside.any():
            continue
        weights = np.stack([wa[inside], wb[inside], wc[inside]], axis=1)
        xyz = weights @ coords
        ix, iy = xx[inside], yy[inside]
        outer = np.abs(xyz[:, 0])
        visible = outer >= depth[iy, ix] - 1e-6
        if not visible.any():
            continue
        weights, xyz, outer, ix, iy = weights[visible], xyz[visible], outer[visible], ix[visible], iy[visible]
        face_uv = np.stack([-.439725589 * xyz[:, 0] + .499223546,
                            .496373541 * xyz[:, 2] + .0849177227], axis=1)
        frontal = _sample(front_pixels, face_uv)
        lateral = _sample(side_pixels, weights @ np.array([side_uv[i] for i in indices]))
        front_weight = 1 - _smooth(-.070, -.006, xyz[:, 1])
        skin = frontal * front_weight[:, None] + lateral * (1 - front_weight[:, None])
        hair_color = _sample(hair_pixels, _dome_uv(xyz))
        # Preserve the authored short fringe; round only the lower sideburn
        # edge above the ear, instead of following its coarse triangle border.
        side_amount = np.clip(np.abs(xyz[:, 0]) / .068, 0, 1)
        front_line = 1.651 - .040 * side_amount ** 1.4
        frontness = 1 - _smooth(-.047, -.020, xyz[:, 1])
        line = front_line * frontness + 1.520 * (1 - frontness)
        side_line = 1.609 + .004 * _smooth(-.020, .010, xyz[:, 1])
        line = np.maximum(line, side_line)
        alpha = _smooth(line - .002, line + .002, xyz[:, 2])
        target = skin * (1 - alpha[:, None]) + hair_color * alpha[:, None]
        localized = (_smooth(.048, .058, np.abs(xyz[:, 0]))
                     * (1 - _smooth(.015, .040, xyz[:, 1]))
                     * _smooth(1.580, 1.602, xyz[:, 2]))
        if category == 'hair':
            rgb = hair_color * (1 - localized[:, None]) + target * localized[:, None]
        else:
            rgb = skin * (1 - localized[:, None]) + target * localized[:, None]
        rgba[iy, ix, :3] = rgb
        depth[iy, ix] = outer
        filled[iy, ix] = True
    covered_pixels = int(filled.sum())
    assert covered_pixels > 40000, covered_pixels
    for _ in range(8):
        before = filled.copy()
        for shift in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            add = ~filled & np.roll(before, shift, axis=(0, 1))
            rgba[add] = np.roll(rgba, shift, axis=(0, 1))[add]
            filled[add] = True
    image = bpy.data.images.new('Gravebound_TempleSkin_Continuous_1024.png', width=size, height=size, alpha=True)
    image.colorspace_settings.name = front_image.colorspace_settings.name
    image.pixels.foreach_set(rgba.reshape(-1))
    image.update()
    image.pack()
    material = bpy.data.materials.new('Gravebound_TempleSkin_Continuous_PBR')
    material.use_nodes = True
    material.use_backface_culling = False
    material.roughness = .88
    tree = material.node_tree
    shader = next(n for n in tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Roughness'].default_value = .88
    shader.inputs['Metallic'].default_value = 0
    shader.inputs['Specular IOR Level'].default_value = .22
    tex = tree.nodes.new('ShaderNodeTexImage')
    tex.image = image
    tex.extension = 'EXTEND'
    tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
    mesh.materials.append(material)
    slot = len(mesh.materials) - 1
    for p in mesh.polygons:
        if p.index not in selected_set:
            continue
        p.material_index = slot
        for li in p.loop_indices:
            mesh.uv_layers.active.data[li].uv = _atlas_uv(mesh.vertices[mesh.loops[li].vertex_index].co)
    mesh.update()
    untouched = [p for p in mesh.polygons if p.index not in selected_set]
    assert all(mesh.materials[p.material_index] is old_materials[p.index]
               and all(tuple(mesh.uv_layers.active.data[i].uv) == old_uv[i] for i in p.loop_indices)
               for p in untouched)
    assert _geometry(mesh) == before_geometry
    report = {
        'selected_faces': len(selected), 'selected_face_indices': selected,
        'material_categories': categories, 'covered_pixels': covered_pixels,
        'texture_size': [size, size], 'packed': bool(image.packed_file),
        'front_side_blend_y_m': [-.070, -.006], 'side_hairline_blend_m': .004,
        'untouched_head_faces': len(untouched), 'central_face_unchanged': True,
        'geometry_unchanged': True, 'geometry_sha256': before_geometry,
        'mesh_objects': len([o for o in bpy.context.scene.objects if o.type == 'MESH']),
        'pass': True,
    }
    (W / 'temples_report.json').write_text(json.dumps(report, indent=2))
    print('TEMPLES REPAIR PASS', len(selected), categories, covered_pixels)
    return report
