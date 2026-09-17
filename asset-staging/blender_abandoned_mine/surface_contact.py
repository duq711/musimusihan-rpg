"""Conform open photographic rock scans to the actual sculpted cave surface.

A scan is a partial skin, not a closed boulder. Placing its origin near a wall
left its rim and much of its skin floating a metre into the passage. This pass
fits every vertex to the real terrain, uses the host's metric photographic
material and shallow relief, and buries the open perimeter into the host rock. Source files are only
saved by the caller after all scene checks have passed.
"""
import bpy
import numpy as np
from mathutils import Vector
import rock_detail

VERSION = 2
MAX_RELIEF = .085
EDGE_BURIAL = .022


def _boundary_fade(mesh):
    faces = np.array([list(p.vertices) for p in mesh.polygons], dtype=np.int32)
    if faces.shape[1] != 3:
        raise RuntimeError('Rock scan must retain its triangulated source topology')
    edges = np.vstack((faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]))
    edges.sort(axis=1)
    unique, counts = np.unique(edges, axis=0, return_counts=True)
    boundary = np.unique(unique[counts == 1])
    # Feather across topological rings; even irregular/torn perimeter edges
    # reach the host rock instead of depending on a rectangular bounding box.
    near = np.zeros(len(mesh.vertices), dtype=bool)
    near[boundary] = True
    distance = np.full(len(mesh.vertices), 9, dtype=np.int32)
    distance[near] = 0
    for ring in range(1, 9):
        touched = near[unique[:, 0]] | near[unique[:, 1]]
        grown = np.unique(unique[touched])
        fresh = grown[~near[grown]]
        distance[fresh] = ring
        near[grown] = True
    return np.minimum(distance / 8, 1.0), boundary


def fix_scene(layout, report):
    terrain = rock_detail._terrain_surface()
    if terrain is None:
        raise RuntimeError('Actual cave triangles are required for scan contact')
    assets = []
    for obj in list(bpy.data.objects):
        if obj.type != 'MESH' or not obj.name.startswith('RockScan_'):
            continue
        if obj.get('surface_contact_version') == VERSION:
            assets.append(obj['surface_contact_report'].to_dict())
            continue
        # The unclipped scan templates are needed by future authored rebuilds.
        obj.data.use_fake_user = True
        obj.data = obj.data.copy()
        obj.data.name = 'SurfaceFitted_' + obj.name
        # Once conformed, fine photographed normal maps carry the micro detail.
        # Avoid making132 formerly linked scan copies a multi-million-face cost.
        modifier = obj.modifiers.new('ContactPatchReduction', 'DECIMATE')
        modifier.ratio = .28
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        mesh = obj.data
        world = obj.matrix_world.copy()
        inverse = world.inverted()
        coords = np.array([world @ v.co for v in mesh.vertices], dtype=np.float64)
        fade, boundary = _boundary_fade(mesh)
        local_y = np.array([v.co.y for v in mesh.vertices])
        span = max(float(np.ptp(local_y)), .01)
        relief = .024 + (1 - (local_y - local_y.min()) / span) * (MAX_RELIEF - .024)
        offsets = -EDGE_BURIAL + fade * (relief + EDGE_BURIAL)
        before_max = 0.0
        fitted = []
        normals = []
        boundary_set = set(int(i) for i in boundary)
        boundary_samples = []
        for i, coord in enumerate(coords):
            hit, normal, face, distance = terrain.find_nearest(Vector(coord))
            if hit is None:
                raise RuntimeError('No terrain host for ' + obj.name)
            before_max = max(before_max, float(distance))
            point = hit + normal * float(offsets[i])
            mesh.vertices[i].co = inverse @ point
            fitted.append(point)
            normals.append(normal)
            if i in boundary_set and len(boundary_samples) < 12:
                boundary_samples.append({
                    'vertex': [point.x, point.z, -point.y],
                    'surface': [hit.x, hit.z, -hit.y],
                    'normal': [normal.x, normal.z, -normal.y],
                })
        mesh.update()
        host_slots = next(o.data.materials for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Terrain_'))
        mesh.materials.clear()
        for material in host_slots:
            mesh.materials.append(material)
        uv = mesh.uv_layers.active or mesh.uv_layers.new(name='Mine_MetricUV')
        # Deforming an irregular photographic skin invalidates its old UV
        # parameterization. Match the surrounding wall's world-metre mapping
        # instead of stretching a scan photograph across newly fitted faces.
        for polygon in mesh.polygons:
            host_normal = sum((normals[i] for i in polygon.vertices), Vector()).normalized()
            dominant = max(range(3), key=lambda axis: abs(host_normal[axis]))
            center = sum((fitted[i] for i in polygon.vertices), Vector()) / len(polygon.vertices)
            ground = host_normal.z > .72 and center.z < .18
            polygon.material_index = 4 if ground else 0
            tile = float(mesh.materials[polygon.material_index].get('scan_tile_m', 1.8))
            for loop_index in polygon.loop_indices:
                point = fitted[mesh.loops[loop_index].vertex_index]
                pair = (point.y, point.z) if dominant == 0 else ((point.x, point.z) if dominant == 1 else (point.x, point.y))
                uv.data[loop_index].uv = (pair[0] / tile, pair[1] / tile)
        mesh['continuous_geology_uv'] = True
        # The photographed skin must face into the cave after conformation.
        # Keep loop UVs attached to their vertices while reversing winding.
        normal_matrix = world.to_3x3().inverted().transposed()
        for polygon in mesh.polygons:
            target = sum((normals[i] for i in polygon.vertices), Vector())
            if (normal_matrix @ polygon.normal).dot(target) < 0:
                polygon.flip()
            polygon.use_smooth = True
        mesh.update()
        entry = {
            'name': obj.name,
            'vertices': len(mesh.vertices),
            'previous_max_gap_m': round(before_max, 5),
            'max_surface_relief_m': MAX_RELIEF,
            'open_rim_vertices': len(boundary),
            'rim_burial_m': EDGE_BURIAL,
            'boundary_samples': boundary_samples,
        }
        obj['surface_contact_version'] = VERSION
        obj['surface_contact_report'] = entry
        assets.append(entry)
        print('SURFACE_CONTACT', obj.name, 'old gap', round(before_max, 3), flush=True)
    bpy.context.view_layer.update()
    report['rock_surface_contact'] = {
        'version': VERSION, 'assets': assets, 'scan_count': len(assets),
        'max_surface_relief_m': MAX_RELIEF, 'edge_burial_m': EDGE_BURIAL,
        'method': 'Every scan vertex fitted to actual terrain; open rims buried; matching metric photographed geology prevents stretched floating skins',
    }
    return report
