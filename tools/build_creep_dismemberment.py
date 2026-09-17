#!/usr/bin/env python3
"""Split the locally licensed Creep skin into detachable, capped regions.

Only this converter is public. Source and derived GLBs remain in assets/licensed.
The source skeleton, inverse binds, animations, material and image bytes are retained.
Run: python3 tools/build_creep_dismemberment.py
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import struct

REGIONS = ('left_arm', 'right_arm', 'left_leg', 'right_leg', 'head')
COMPONENT = {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
EPSILON = 1e-7


def add(a, b): return tuple(x+y for x, y in zip(a, b))
def sub(a, b): return tuple(x-y for x, y in zip(a, b))
def mul(a, s): return tuple(x*s for x in a)
def dot(a, b): return sum(x*y for x, y in zip(a, b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def normalized(a): return mul(a, 1/max(math.sqrt(dot(a, a)), 1e-20))
def mean(values): return tuple(sum(v[i] for v in values)/len(values) for i in range(len(values[0])))
def position_key(v): return tuple(round(x, 6) for x in v['p'])


class GLB:
    def __init__(self, path):
        blob = Path(path).read_bytes()
        magic, version, total = struct.unpack_from('<4sII', blob)
        assert magic == b'glTF' and version == 2 and total == len(blob)
        length, kind = struct.unpack_from('<II', blob, 12)
        assert kind == 0x4e4f534a
        self.doc = json.loads(blob[20:20+length])
        length_bin, kind = struct.unpack_from('<II', blob, 20+length)
        assert kind == 0x004e4942
        self.raw = bytearray(blob[28+length:28+length+length_bin])

    def read(self, index):
        a = self.doc['accessors'][index]
        assert not a.get('sparse') and not a.get('normalized')
        view = self.doc['bufferViews'][a['bufferView']]
        fmt = '<'+COMPONENT[a['componentType']]*WIDTH[a['type']]
        start = view.get('byteOffset', 0)+a.get('byteOffset', 0)
        stride = view.get('byteStride', struct.calcsize(fmt))
        return [struct.unpack_from(fmt, self.raw, start+i*stride) for i in range(a['count'])]

    def accessor(self, rows, component, kind, target=None):
        while len(self.raw) % 4: self.raw.append(0)
        start = len(self.raw)
        fmt = '<'+COMPONENT[component]*WIDTH[kind]
        for row in rows: self.raw.extend(struct.pack(fmt, *row))
        view = {'buffer': 0, 'byteOffset': start, 'byteLength': len(self.raw)-start}
        if target is not None: view['target'] = target
        self.doc['bufferViews'].append(view)
        accessor = {'bufferView': len(self.doc['bufferViews'])-1, 'componentType': component,
                    'count': len(rows), 'type': kind}
        if component == 5126:
            accessor['min'] = [min(row[i] for row in rows) for i in range(WIDTH[kind])]
            accessor['max'] = [max(row[i] for row in rows) for i in range(WIDTH[kind])]
        self.doc['accessors'].append(accessor)
        return len(self.doc['accessors'])-1

    def write(self, path):
        self.doc['buffers'] = [{'byteLength': len(self.raw)}]
        encoded = json.dumps(self.doc, separators=(',', ':')).encode()
        encoded += b' '*((-len(encoded)) % 4)
        binary = bytes(self.raw)+b'\0'*((-len(self.raw)) % 4)
        blob = struct.pack('<4sII', b'glTF', 2, 28+len(encoded)+len(binary))
        blob += struct.pack('<II', len(encoded), 0x4e4f534a)+encoded
        blob += struct.pack('<II', len(binary), 0x004e4942)+binary
        Path(path).write_bytes(blob)


def region_bones(names, region):
    if region == 'head': return {i for i, name in enumerate(names) if name in ('Neck', 'Head', 'Jaw1', 'Jaw2', 'Tongue')}
    suffix = '.L' if region.startswith('left') else '.R'
    prefixes = ('Arm', 'Hand', 'Fing', 'Find') if region.endswith('arm') else ('Leg', 'Foot', 'Step')
    return {i for i, name in enumerate(names) if name.endswith(suffix) and name.startswith(prefixes)}


def interpolate(a, b, t):
    # Blend by joint identity, never by joint-array slot. Identical cut vertices on
    # both sides retain identical weights and therefore remain seamless in motion.
    weights = {i: a['w'].get(i, 0)*(1-t)+b['w'].get(i, 0)*t for i in a['w'].keys() | b['w'].keys()}
    return {'p': add(mul(a['p'], 1-t), mul(b['p'], t)),
            'n': normalized(add(mul(a['n'], 1-t), mul(b['n'], t))),
            'uv': add(mul(a['uv'], 1-t), mul(b['uv'], t)), 'w': weights}


def scalar(v, bones): return sum(w for i, w in v['w'].items() if i in bones)-0.5


def split_polygon(poly, bones):
    """Clip one triangle/polygon by the linearly interpolated region influence."""
    positive, negative, cuts = [], [], []
    for a, b in zip(poly, poly[1:]+poly[:1]):
        da, db = scalar(a, bones), scalar(b, bones)
        if da >= 0: positive.append(a)
        if da <= 0: negative.append(a)
        if da*db < 0:
            v = interpolate(a, b, da/(da-db))
            positive.append(v); negative.append(v); cuts.append(v)
    return positive, negative, cuts


def triangles(poly):
    return [(poly[0], poly[i], poly[i+1]) for i in range(1, len(poly)-1)
            if dot(cross(sub(poly[i]['p'], poly[0]['p']), sub(poly[i+1]['p'], poly[0]['p'])),
                   cross(sub(poly[i]['p'], poly[0]['p']), sub(poly[i+1]['p'], poly[0]['p']))) > 1e-20]


def boundary_loops(segments):
    vertices, edges = {}, set()
    for a, b in segments:
        ka, kb = position_key(a), position_key(b)
        if ka == kb: continue
        vertices.setdefault(ka, a); vertices.setdefault(kb, b)
        edges.add(tuple(sorted((ka, kb))))
    adjacency = {k: set() for k in vertices}
    for a, b in edges: adjacency[a].add(b); adjacency[b].add(a)
    bad = {k: len(v) for k, v in adjacency.items() if len(v) != 2}
    if bad: raise ValueError(f'Cut boundary is not a closed manifold loop: {bad}')
    loops = []
    while edges:
        a, b = min(edges); edges.remove((a, b)); sequence = [a, b]
        while sequence[-1] != sequence[0]:
            current = sequence[-1]
            next_key = next(k for k in adjacency[current] if tuple(sorted((current, k))) in edges)
            edges.remove(tuple(sorted((current, next_key))))
            sequence.append(next_key)
        loops.append([vertices[k] for k in sequence[:-1]])
    return loops


def make_caps(loop, outward):
    # Interior tessellation of the actual cut loop; no open stump and no thin
    # crossing plate. Perimeter points and weights match both original surfaces.
    center = mean([v['p'] for v in loop])
    normal = normalized(tuple(sum(cross(sub(loop[i]['p'], center), sub(loop[(i+1)%len(loop)]['p'], center))[axis]
                                  for i in range(len(loop))) for axis in range(3)))
    if dot(normal, outward) < 0: loop = list(reversed(loop)); normal = mul(normal, -1)
    drop_axis = max(range(3), key=lambda i: abs(normal[i]))
    axes = [i for i in range(3) if i != drop_axis]
    points = [(v['p'][axes[0]], v['p'][axes[1]]) for v in loop]
    def area2(a, b, c): return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    signed = sum(points[i][0]*points[(i+1)%len(points)][1]-points[(i+1)%len(points)][0]*points[i][1] for i in range(len(points)))
    sign = 1 if signed > 0 else -1
    pending = list(range(len(loop))); result = []
    while len(pending) > 3:
        found = False
        for k, b in enumerate(pending):
            a, c = pending[k-1], pending[(k+1)%len(pending)]
            if sign*area2(points[a], points[b], points[c]) <= 1e-12: continue
            inside = any(min(sign*area2(points[a], points[b], points[p]), sign*area2(points[b], points[c], points[p]),
                             sign*area2(points[c], points[a], points[p])) > -1e-12 for p in pending if p not in (a, b, c))
            if inside: continue
            result.append((a, b, c)); pending.pop(k); found = True; break
        if not found: raise ValueError('Cut loop cannot be tessellated without overlapping triangles')
    result.append(tuple(pending))
    radius = max(math.sqrt(dot(sub(v['p'], center), sub(v['p'], center))) for v in loop)
    body, part = [], []
    for tri in result:
        vs = []
        for i in tri:
            v = dict(loop[i]); v['n'] = normal
            v['uv'] = tuple((v['p'][axis]-center[axis])/(radius*2)+.5 for axis in axes)
            vs.append(v)
        body.append(tuple(vs))
        part.append(tuple(dict(v, n=mul(normal, -1)) for v in reversed(vs)))
    return body, part


def write_mesh(glb, name, tris, material):
    vertices, indices, by_key = [], [], {}
    max_discarded = 0.0
    for triangle in tris:
        for v in triangle:
            weights = sorted(((i, w) for i, w in v['w'].items() if w > 1e-10), key=lambda pair: (-pair[1], pair[0]))
            max_discarded = max(max_discarded, sum(w for _, w in weights[8:]))
            weights = weights[:8]; total = sum(w for _, w in weights)
            weights = [(i, w/total) for i, w in weights]+[(0, 0)]*(8-len(weights))
            joints, values = zip(*weights)
            key = (v['p'], v['n'], v['uv'], joints, values)
            if key not in by_key: by_key[key] = len(vertices); vertices.append(key)
            indices.append(by_key[key])
    attrs = {}
    for name_attr, data, component, kind in (
        ('POSITION', [v[0] for v in vertices], 5126, 'VEC3'),
        ('NORMAL', [v[1] for v in vertices], 5126, 'VEC3'),
        ('TEXCOORD_0', [v[2] for v in vertices], 5126, 'VEC2'),
        ('JOINTS_0', [v[3][:4] for v in vertices], 5123, 'VEC4'),
        ('JOINTS_1', [v[3][4:] for v in vertices], 5123, 'VEC4'),
        ('WEIGHTS_0', [v[4][:4] for v in vertices], 5126, 'VEC4'),
        ('WEIGHTS_1', [v[4][4:] for v in vertices], 5126, 'VEC4')):
        attrs[name_attr] = glb.accessor(data, component, kind, 34962)
    primitive = {'attributes': attrs, 'indices': glb.accessor([(i,) for i in indices], 5125, 'SCALAR', 34963), 'material': material}
    glb.doc['meshes'].append({'name': name, 'primitives': [primitive]})
    return {'name': name, 'vertices': len(vertices), 'triangles': len(tris), 'max_discarded_weight': max_discarded}


def main():
    workspace = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=workspace/'godot-game/assets/licensed/creep/creep.glb')
    parser.add_argument('--output', type=Path, default=workspace/'godot-game/assets/licensed/creep/creep_dismembered.glb')
    parser.add_argument('--report', type=Path, default=workspace/'exports/Creep_20260917/dismemberment_report.json')
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve(): raise ValueError('Source GLB must be preserved')
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    glb = GLB(args.source); doc = glb.doc
    assert len(doc['meshes']) == 1 and len(doc['meshes'][0]['primitives']) == 1 and len(doc['skins']) == 1
    original_animations, original_skins, original_materials = copy.deepcopy(doc['animations']), copy.deepcopy(doc['skins']), copy.deepcopy(doc['materials'])
    primitive = doc['meshes'][0]['primitives'][0]; attributes = {key: glb.read(index) for key, index in primitive['attributes'].items()}
    skin_nodes = doc['skins'][0]['joints']; names = [doc['nodes'][index]['name'] for index in skin_nodes]
    groups = {name: region_bones(names, name) for name in REGIONS}
    vertices = []
    for i, p in enumerate(attributes['POSITION']):
        joints = attributes['JOINTS_0'][i]+attributes['JOINTS_1'][i]
        weights = attributes['WEIGHTS_0'][i]+attributes['WEIGHTS_1'][i]
        values = {}
        for joint, weight in zip(joints, weights): values[joint] = values.get(joint, 0)+weight
        vertices.append({'p': p, 'n': attributes['NORMAL'][i], 'uv': attributes['TEXCOORD_0'][i], 'w': values})
    index = [row[0] for row in glb.read(primitive['indices'])]
    remaining = [tuple(vertices[i] for i in index[k:k+3]) for k in range(0, len(index), 3)]
    split, cap_meshes, metadata = {}, {}, {}
    for region in REGIONS:
        taken, rest, segments = [], [], []
        for triangle in remaining:
            positive, negative, cut = split_polygon(list(triangle), groups[region])
            taken.extend(triangles(positive)); rest.extend(triangles(negative))
            if len(cut) == 2: segments.append(cut)
        loops = boundary_loops(segments)
        if len(loops) != 1: raise ValueError(f'{region}: expected one anatomical section, got {len(loops)}')
        split[region] = taken; remaining = rest
        outward = sub(mean([v['p'] for tri in taken for v in tri]), mean([v['p'] for tri in rest for v in tri]))
        body_cap, part_cap = make_caps(loops[0], outward)
        cap_meshes['CreepCap_body_'+region] = body_cap
        cap_meshes['CreepCap_part_'+region] = part_cap
        metadata[region] = {'bones': [names[i] for i in sorted(groups[region])], 'boundary_vertices': len(loops[0]),
                            'cut_center_mesh_local': mean([v['p'] for v in loops[0]]), 'cap_triangles': len(body_cap)}
    split['torso'] = remaining
    original_node = next(i for i, node in enumerate(doc['nodes']) if node.get('mesh') == 0)
    parent = next(node for node in doc['nodes'] if original_node in node.get('children', []))
    source_node = dict(doc['nodes'][original_node]); doc['meshes'] = []
    cap_material = len(doc['materials'])
    doc['materials'].append({'name': 'CreepCutInterior', 'pbrMetallicRoughness': {'baseColorFactor': [.16, .07, .055, 1], 'metallicFactor': 0, 'roughnessFactor': .94}, 'doubleSided': True})
    outputs = []
    all_meshes = [('CreepPart_'+name, tris, primitive['material']) for name, tris in split.items()]
    all_meshes += [(name, tris, cap_material) for name, tris in cap_meshes.items()]
    for mesh_i, (name, tris, mat) in enumerate(all_meshes):
        outputs.append(write_mesh(glb, name, tris, mat))
        node = dict(source_node, mesh=mesh_i, name=name)
        if name.startswith('CreepCap_'): node['extras'] = {'dismemberment_cap': True, 'hidden_until_severed': True}
        if mesh_i == 0: doc['nodes'][original_node] = node
        else: parent['children'].append(len(doc['nodes'])); doc['nodes'].append(node)
    assert doc['animations'] == original_animations and doc['skins'] == original_skins and doc['materials'][:len(original_materials)] == original_materials
    assert len(skin_nodes) == 55 and len(doc['animations']) == 17
    # Godot supports eight influences. Clipped neck vertices can combine more;
    # retain the strongest eight identically on both sides and cap perimeter.
    assert max(item['max_discarded_weight'] for item in outputs) < .02
    assert hashlib.sha256(args.source.read_bytes()).hexdigest() == source_hash
    args.output.parent.mkdir(parents=True, exist_ok=True); glb.write(args.output)
    report = {'source_sha256': source_hash, 'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
              'skeleton_bones': len(skin_nodes), 'animation_clips': len(doc['animations']), 'regions': metadata,
              'meshes': outputs, 'source_triangles': len(index)//3, 'surface_triangles': sum(len(t) for t in split.values()),
              'source_preserved': True, 'animation_skin_material_records_preserved': True,
              'contract': 'Shared Skeleton3D; caps hidden until severed. Bake part and part cap before hiding originals; show corresponding body cap.'}
    args.report.parent.mkdir(parents=True, exist_ok=True); args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__': main()
