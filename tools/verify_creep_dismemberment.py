#!/usr/bin/env python3
"""Validate local Creep split geometry without opening Blender or Godot windows."""
import argparse
import bisect
from collections import Counter
import hashlib
import json
import math
from pathlib import Path

from build_creep_dismemberment import GLB, REGIONS, add, cross, dot, sub


def mesh_data(glb, mesh):
    primitive = mesh['primitives'][0]
    attrs = {name: glb.read(index) for name, index in primitive['attributes'].items()}
    indices = [row[0] for row in glb.read(primitive['indices'])]
    return attrs, indices


def edges_and_area(glb, meshes):
    edges = Counter(); area = 0.0
    for mesh in meshes:
        attrs, indices = mesh_data(glb, mesh); vertices = attrs['POSITION']
        for i in range(0, len(indices), 3):
            a, b, c = (vertices[index] for index in indices[i:i+3])
            normal = cross(sub(b, a), sub(c, a)); area += math.sqrt(dot(normal, normal))*.5
            a, b, c = (tuple(round(x, 6) for x in p) for p in (a, b, c))
            for edge in ((a, b), (b, c), (c, a)): edges[tuple(sorted(edge))] += 1
    return edges, area


def multiply(a, b): return [[sum(a[r][k]*b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def local_matrix(node):
    if 'matrix' in node: return [[node['matrix'][c*4+r] for c in range(4)] for r in range(4)]
    x, y, z, w = node.get('rotation', (0, 0, 0, 1))
    matrix = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0],
              [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0],
              [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0], [0, 0, 0, 1]]
    for r in range(3):
        for c in range(3): matrix[r][c] *= node.get('scale', (1, 1, 1))[c]
        matrix[r][3] = node.get('translation', (0, 0, 0))[r]
    return matrix


def interpolated(a, b, t, rotation=False):
    if rotation:
        product = dot(a, b)
        if product < 0: b = tuple(-v for v in b); product = -product
        if product < .9995:
            theta = math.acos(min(product, 1))
            wa, wb = math.sin((1-t)*theta)/math.sin(theta), math.sin(t*theta)/math.sin(theta)
        else: wa, wb = 1-t, t
        value = tuple(wa*x+wb*y for x, y in zip(a, b))
        return tuple(v/math.sqrt(dot(value, value)) for v in value)
    return tuple(x*(1-t)+y*t for x, y in zip(a, b))


def skin_matrices(glb, animation, time):
    doc = glb.doc; nodes = [dict(n) for n in doc['nodes']]
    for channel in animation['channels']:
        sampler = animation['samplers'][channel['sampler']]
        times = [row[0] for row in glb.read(sampler['input'])]
        values = glb.read(sampler['output']); path = channel['target']['path']
        if len(times) == 1: value = values[0]
        else:
            k = max(0, min(len(times)-2, bisect.bisect_right(times, time)-1))
            t = max(0, min(1, (time-times[k])/(times[k+1]-times[k])))
            value = values[k] if sampler.get('interpolation') == 'STEP' else interpolated(values[k], values[k+1], t, path == 'rotation')
        nodes[channel['target']['node']][path] = value
    parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}
    global_matrices = {}
    def global_node(index):
        if index not in global_matrices:
            local = local_matrix(nodes[index])
            global_matrices[index] = multiply(global_node(parents[index]), local) if index in parents else local
        return global_matrices[index]
    skin = doc['skins'][0]; inverse_binds = glb.read(skin['inverseBindMatrices'])
    return [multiply(global_node(node), [[inverse_binds[i][c*4+r] for c in range(4)] for r in range(4)]) for i, node in enumerate(skin['joints'])]


def skin_vertex(vertex, matrices):
    position, joints, weights = vertex
    result = [0.0, 0.0, 0.0]
    for joint, weight in zip(joints, weights):
        if weight <= 0: continue
        transform = matrices[joint]
        for axis in range(3): result[axis] += weight*(dot(transform[axis][:3], position)+transform[axis][3])
    return result


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=root/'godot-game/assets/licensed/creep/creep.glb')
    parser.add_argument('--derived', type=Path, default=root/'godot-game/assets/licensed/creep/creep_dismembered.glb')
    parser.add_argument('--report', type=Path, default=root/'exports/Creep_20260917/dismemberment_geometry_validation.json')
    args = parser.parse_args(); source, derived = GLB(args.source), GLB(args.derived)
    assert source.doc['animations'] == derived.doc['animations']
    assert source.doc['skins'] == derived.doc['skins']
    assert source.doc['materials'] == derived.doc['materials'][:len(source.doc['materials'])]
    assert derived.raw[:len(source.raw)] == source.raw
    meshes = {mesh['name']: mesh for mesh in derived.doc['meshes']}
    expected = {'CreepPart_'+r for r in (*REGIONS, 'torso')}
    expected |= {'CreepCap_'+side+'_'+r for r in REGIONS for side in ('body', 'part')}
    assert set(meshes) == expected
    assert {node['mesh'] for node in derived.doc['nodes'] if 'mesh' in node} == set(range(16))
    source_edges, source_area = edges_and_area(source, source.doc['meshes'])
    surface_edges, surface_area = edges_and_area(derived, [meshes['CreepPart_'+r] for r in (*REGIONS, 'torso')])
    area_error = abs(surface_area-source_area)/source_area
    assert area_error < 1e-6, area_error
    # Existing teeth/mouth boundaries are preserved; every new stump is closed.
    source_open = {edge: count for edge, count in source_edges.items() if count != 2}
    assert {edge: count for edge, count in surface_edges.items() if count != 2} == source_open
    regions = {}; seam_groups = []
    for region in (*REGIONS, 'torso'):
        names = ['CreepPart_'+region]
        names += ['CreepCap_body_'+r for r in REGIONS] if region == 'torso' else ['CreepCap_part_'+region]
        region_edges, _ = edges_and_area(derived, [meshes[name] for name in names])
        exceptional = {edge: count for edge, count in region_edges.items() if count != 2}
        assert exceptional == (source_open if region == 'head' else {}), region
        regions[region] = {'edge_face_counts': dict(Counter(region_edges.values())), 'new_cut_is_closed': True}
    for region in REGIONS:
        cap, _ = mesh_data(derived, meshes['CreepCap_body_'+region])
        part_cap, _ = mesh_data(derived, meshes['CreepCap_part_'+region])
        cap_edges, _ = edges_and_area(derived, [meshes['CreepCap_body_'+region]])
        boundary_keys = {key for edge, count in cap_edges.items() if count == 1 for key in edge}
        assert len(cap['POSITION']) > len(boundary_keys)*2, region
        assert 'COLOR_0' in cap and 'COLOR_0' in part_cap, region
        colors = cap['COLOR_0']
        assert len(set(colors)) >= 8 and all(c[3] == 1 for c in colors), region
        assert any(c[0] > .4 and c[1] > .25 for c in colors), (region, 'bone missing')
        assert any(c[0] < .1 and c[1] < .02 for c in colors), (region, 'dark rim missing')
        assert all(0 <= channel <= 1 for color in colors for channel in color), region
        assert all(0 <= channel <= 1 for uv in cap['TEXCOORD_0'] for channel in uv), region
        for attrs in (cap, part_cap):
            assert all(abs(dot(n, n)-1) < 1e-5 for n in attrs['NORMAL']), region
            for a, b in zip(attrs['WEIGHTS_0'], attrs['WEIGHTS_1']):
                assert abs(sum(a+b)-1) < 1e-6 and all(w >= 0 for w in a+b), region
        # Body and loose-part interiors recess in opposite directions. A flat
        # plate (even a non-planar boundary fan) cannot pass this measurement.
        positions_by_uv = {uv: p for uv, p in zip(part_cap['TEXCOORD_0'], part_cap['POSITION'])}
        separation = [math.dist(p, positions_by_uv[uv]) for uv, p in zip(cap['TEXCOORD_0'], cap['POSITION'])]
        assert max(separation) > .02, (region, max(separation))
        assert max(separation) < .071, (region, max(separation))
        regions[region]['wound_surface'] = {'vertices': len(cap['POSITION']), 'rim_vertices': len(boundary_keys),
            'unique_tissue_colors': len(set(colors)), 'maximum_two_sided_recess_m': max(separation),
            'bone_marrow_and_dark_rim_present': True}
        groups = {key: [] for key in boundary_keys}
        for name in ('CreepPart_torso', 'CreepPart_'+region, 'CreepCap_body_'+region, 'CreepCap_part_'+region):
            attrs, _ = mesh_data(derived, meshes[name])
            for i, position in enumerate(attrs['POSITION']):
                key = tuple(round(x, 6) for x in position)
                if key in groups:
                    joints = attrs['JOINTS_0'][i]+attrs['JOINTS_1'][i]
                    weights = attrs['WEIGHTS_0'][i]+attrs['WEIGHTS_1'][i]
                    assert abs(sum(weights)-1) < 1e-6
                    groups[key].append((position, joints, weights))
        assert all(len(group) >= 4 for group in groups.values())
        seam_groups.extend(groups.values())
    maximum_seam_gap = 0.0; samples = 0
    for clip in derived.doc['animations']:
        duration = max(derived.read(sampler['input'])[-1][0] for sampler in clip['samplers'])
        for ratio in (0, .25, .5, .75, 1):
            matrices = skin_matrices(derived, clip, duration*ratio)
            for group in seam_groups:
                positions = [skin_vertex(v, matrices) for v in group]
                maximum_seam_gap = max(maximum_seam_gap, max(math.dist(positions[0], p) for p in positions[1:]))
            samples += 1
    assert maximum_seam_gap < 1e-5, maximum_seam_gap
    report = {'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
              'derived_sha256': hashlib.sha256(args.derived.read_bytes()).hexdigest(),
              'original_animation_skin_material_and_binary_preserved': True,
              'region_mesh_count': 6, 'cap_mesh_count': 10, 'regions': regions,
              'relative_surface_area_error': area_error, 'animation_pose_samples': samples,
              'maximum_animated_seam_gap_m': maximum_seam_gap,
              'preserved_source_mouth_open_edges': sum(count == 1 for count in source_open.values()),
              'preserved_source_nonmanifold_edges': sum(count > 2 for count in source_open.values()),
              'note': 'Geometry/CPU skin validation only; live Godot rendering and physical detachment are separate checks.'}
    args.report.parent.mkdir(parents=True, exist_ok=True); args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__': main()
