"""Read GLB metadata only; no Blender, modeling, rendering or source changes."""
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parent


def inspect(path):
    raw = path.read_bytes()
    magic, version, total = struct.unpack_from('<III', raw)
    assert magic == 0x46546C67 and version == 2 and total == len(raw)
    length, kind = struct.unpack_from('<II', raw, 12)
    assert kind == 0x4E4F534A
    gltf = json.loads(raw[20:20 + length])
    nodes = gltf['nodes']
    roots = gltf['scenes'][gltf.get('scene', 0)]['nodes']
    active = set()

    def visit(index):
        if index in active:
            return
        active.add(index)
        for child in nodes[index].get('children', []):
            visit(child)

    for index in roots:
        visit(index)
    meshes = []
    for index in sorted(active):
        node = nodes[index]
        if 'mesh' not in node:
            continue
        source = gltf['meshes'][node['mesh']]
        primitives = source['primitives']
        assert all(p.get('mode', 4) == 4 for p in primitives)
        vertices = [gltf['accessors'][p['attributes']['POSITION']] for p in primitives]
        bounds_min = [min(p['min'][axis] for p in vertices) for axis in range(3)]
        bounds_max = [max(p['max'][axis] for p in vertices) for axis in range(3)]
        meshes.append({
            'node': node.get('name'), 'mesh': source.get('name'),
            'triangles': sum(gltf['accessors'][p['indices']]['count'] // 3 for p in primitives),
            'local_bind_bounds_m': [bounds_min, bounds_max],
            'local_bind_extent_m': [b - a for a, b in zip(bounds_min, bounds_max)],
            'skin': node.get('skin'),
        })
    return {
        'file': path.name, 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw),
        'active_mesh_nodes': len(meshes),
        'active_triangle_count': sum(p['triangles'] for p in meshes),
        'meshes': meshes,
        'skins': [[nodes[i].get('name') for i in skin['joints']] for skin in gltf.get('skins', [])],
        'scene_roots': [nodes[i] for i in roots],
        'measurement_note': 'Accessor AABBs in local bind coordinates; not evaluated skin-pose or world bounds. Unreferenced mesh leftovers are excluded.',
    }


if __name__ == '__main__':
    report = {name: inspect(ROOT / 'input' / name) for name in
              ['gravebound_player.glb', 'left_arm.glb', 'right_arm.glb']}
    (ROOT / 'source_inspection.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    for name, data in report.items():
        print(name, data['active_mesh_nodes'], 'mesh nodes,', data['active_triangle_count'], 'triangles,', len(data['skins']), 'skins')
