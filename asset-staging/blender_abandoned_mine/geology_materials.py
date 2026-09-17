"""Continuous mineral and soil variation carried by portable PBR and COLOR_0.

Floor corners have their own earth tint even where they share vertices with a
rock wall. All sampling uses world metres, so neighboring chunks and fitted
scan skins agree and don't leave rectangular material patches.
"""
import bpy
import numpy as np
from pathlib import Path
ROOT = Path(__file__).resolve().parent
GROUND_TILE = .82
ROCK_TILE = 1.8


def _tinted_material(source, name, photo=None, roughness=.8, normal_strength=.7):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = source.copy()
        mat.name = name
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    albedo = next(n for n in nodes if n.type == 'TEX_IMAGE' and n.name.endswith('_albedo'))
    if photo is not None:
        albedo.image = photo
    tint = nodes.get('GeologicalTint') or nodes.new('ShaderNodeVertexColor')
    tint.name = 'GeologicalTint'
    tint.layer_name = 'GeologicalTint'
    mix = nodes.get('GeologicalTintMultiply') or nodes.new('ShaderNodeMix')
    mix.name = 'GeologicalTintMultiply'
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1
    links.new(albedo.outputs['Color'], mix.inputs[6])
    links.new(tint.outputs['Color'], mix.inputs[7])
    links.new(mix.outputs[2], bsdf.inputs['Base Color'])
    for link in list(bsdf.inputs['Roughness'].links):
        links.remove(link)
    bsdf.inputs['Roughness'].default_value = roughness
    for node in nodes:
        if node.type == 'NORMAL_MAP':
            node.inputs['Strength'].default_value = normal_strength
    return mat


def _edge_distance(coords, polygon):
    result = np.full(len(coords), 1e5)
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        a, b = np.array(a), np.array(b)
        v = b - a
        t = np.clip(((coords - a) @ v) / max(float(v @ v), 1e-8), 0, 1)
        result = np.minimum(result, np.linalg.norm(coords - a - t[:, None] * v, axis=1))
    return result


def apply_continuous_geology():
    import json
    data = np.load(ROOT / 'terrain_mesh.npz')
    layout = json.loads((ROOT / 'layout.json').read_text())
    xs, zs = data['xs'], data['zs']
    # Mineral tones remain restrained under warm lamps: grey bedrock, pale
    # calcite, dark wet galleries, and cooler cut faces. Soil keeps an umber hue.
    palette = np.array([[.43, .54, .63], [.72, .73, .65], [.21, .29, .34], [.33, .40, .43]], dtype=np.float32)
    field = palette[data['geology']]
    axis = np.arange(-24, 25, dtype=np.float32)
    kernel = np.exp(-axis**2 / (2 * 7.5**2))
    kernel /= kernel.sum()
    for direction in [0, 1]:
        field = np.apply_along_axis(lambda line: np.convolve(np.pad(line, (24, 24), mode='edge'), kernel, mode='valid'), direction, field)
    source = bpy.data.materials['Mine_Limestone']
    photo = next(n.image for n in source.node_tree.nodes if n.type == 'TEX_IMAGE' and n.name.endswith('_albedo'))
    original_names = ['Mine_Limestone', 'Mine_Calcite', 'Mine_DarkGallery', 'Mine_PickCutRock']
    new_mats = []
    for i, name in enumerate(original_names):
        original = bpy.data.materials.get(name) or bpy.data.materials.get('Mine_Continuous_' + name) or source
        mat = _tinted_material(original, 'Mine_Continuous_' + name,
                              photo=photo, roughness=[.77, .52, .63, .84][i],
                              normal_strength=[.82, .42, .8, .92][i])
        mat['scan_tile_m'] = ROCK_TILE
        mat['surface_role'] = 'mineral_rock'
        new_mats.append(mat)
    ground = _tinted_material(bpy.data.materials['Mine_GravelMud'], 'Mine_Continuous_Ground',
                              roughness=.94, normal_strength=.32)
    ground['scan_tile_m'] = GROUND_TILE
    ground['surface_role'] = 'fine_earth_and_gravel'
    vertices_tinted = corners_tinted = ground_corners = 0
    ground_min, ground_max = np.ones(3), np.zeros(3)
    rock_min, rock_max = np.ones(3), np.zeros(3)
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or not (obj.name.startswith('Terrain_') or obj.get('surface_contact_version')):
            continue
        mesh = obj.data
        coords = np.array([obj.matrix_world @ v.co for v in mesh.vertices])
        fx = np.clip((coords[:, 0] - xs[0]) / (xs[1] - xs[0]), 0, len(xs) - 1.001)
        fz = np.clip((-coords[:, 1] - zs[0]) / (zs[1] - zs[0]), 0, len(zs) - 1.001)
        ix, iz = fx.astype(int), fz.astype(int)
        tx, tz = (fx - ix)[:, None], (fz - iz)[:, None]
        rock = (field[iz, ix] * (1 - tx) + field[iz, ix + 1] * tx) * (1 - tz) + (field[iz + 1, ix] * (1 - tx) + field[iz + 1, ix + 1] * tx) * tz
        x, y, z = coords.T
        # Unequal broad deposits, independent of UV tile period; never thin,
        # regularly repeated sine stripes across the whole cave.
        macro = .90 + .07 * np.sin(x * .29 + np.sin(y * .17) * 2.7) + .04 * np.sin(y * .47 - z * .36 + np.sin(x * .12))
        rock *= macro[:, None]
        patch = np.clip(.5 + .28 * np.sin(x * .42 + np.sin(y * .21) * 1.8) + .22 * np.cos(y * .31 + np.sin(x * .14)), 0, 1)
        earth = np.array([.37, .29, .20])[None, :] * (.76 + patch[:, None] * .43)
        # Damp banks follow all six actual authored shorelines.
        bank = np.full(len(coords), 100.0)
        for pool in layout['pools']:
            bank = np.minimum(bank, _edge_distance(coords[:, [0, 1]] * [1, -1], pool['polygon']))
        earth *= (1 - .28 * np.exp(-bank / 1.25))[:, None]
        vertex_indices = np.empty(len(mesh.loops), dtype=np.int32)
        mesh.loops.foreach_get('vertex_index', vertex_indices)
        is_ground = np.zeros(len(mesh.loops), dtype=bool)
        uv = mesh.uv_layers.active or mesh.uv_layers.new(name='Mine_MetricUV')
        # Rebuild from real world positions: idempotent, physical scales remain
        # distinct, and neither re-polishing nor a material swap double-scales.
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        for face in mesh.polygons:
            ground_face = face.material_index >= 4
            world_normal = normal_matrix @ face.normal
            dominant = max(range(3), key=lambda a: abs(world_normal[a]))
            tile = GROUND_TILE if ground_face else ROCK_TILE
            for loop in face.loop_indices:
                p = coords[vertex_indices[loop]]
                pair = (p[1], p[2]) if dominant == 0 else ((p[0], p[2]) if dominant == 1 else (p[0], p[1]))
                uv.data[loop].uv = (pair[0] / tile, pair[1] / tile)
                is_ground[loop] = ground_face
        for i, mat in enumerate(new_mats):
            mesh.materials[i] = mat
        mesh.materials[4] = ground
        mesh['continuous_geology_uv'] = True
        values = rock[vertex_indices].copy()
        values[is_ground] = earth[vertex_indices[is_ground]]
        rgba = np.column_stack((values, np.ones(len(values)))).astype(np.float32)
        color = mesh.color_attributes.get('GeologicalTint')
        if color is not None and color.domain != 'CORNER':
            mesh.color_attributes.remove(color)
            color = None
        if color is None:
            color = mesh.color_attributes.new(name='GeologicalTint', type='FLOAT_COLOR', domain='CORNER')
        color.data.foreach_set('color', rgba.ravel())
        mesh.color_attributes.active_color_index = mesh.color_attributes.find('GeologicalTint')
        mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index
        if np.any(is_ground):
            ground_min = np.minimum(ground_min, values[is_ground].min(axis=0))
            ground_max = np.maximum(ground_max, values[is_ground].max(axis=0))
        if np.any(~is_ground):
            rock_min = np.minimum(rock_min, values[~is_ground].min(axis=0))
            rock_max = np.maximum(rock_max, values[~is_ground].max(axis=0))
        vertices_tinted += len(coords)
        corners_tinted += len(values)
        ground_corners += int(is_ground.sum())
    return {'method': 'Continuous world-metre mineral deposits and damp earth patches; distinct photographic rock/soil, grain scale, normal strength, roughness; portable glTF CORNER COLOR_0',
            'blend_radius_m': 2.55, 'vertices_tinted': vertices_tinted, 'corners_tinted': corners_tinted,
            'ground_corners': ground_corners, 'rock_material_slots': 4, 'contact_patches_share_host_tint': True,
            'rock_tile_m': ROCK_TILE, 'ground_tile_m': GROUND_TILE,
            'ground_tint_range': [ground_min.tolist(), ground_max.tolist()],
            'rock_tint_range': [rock_min.tolist(), rock_max.tolist()]}
